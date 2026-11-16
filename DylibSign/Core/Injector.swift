import Foundation

/// Runs the whole pipeline: unzip IPA → copy tweaks → patch Mach-O → edit Info.plist → (optional) sign → zip.
/// Not thread-safe (zsign uses global state); run one job at a time.
final class Injector {
    private let fm = FileManager.default
    private let log: (String) -> Void

    static let substrateLoadPath = "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
    private static let substrateNames: Set<String> = ["CydiaSubstrate", "libsubstrate.dylib", "libellekit.dylib"]

    init(log: @escaping (String) -> Void) {
        self.log = log
    }

    static var outputDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Output", isDirectory: true)
    }

    func run(_ job: InjectionJob) throws -> URL {
        let work = fm.temporaryDirectory.appendingPathComponent("job-\(UUID().uuidString)", isDirectory: true)
        let extractDir = work.appendingPathComponent("ipa", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // 1. Unzip
        log("📦 فك ضغط \(job.ipa.lastPathComponent)…")
        guard ZSignBridge.extractZip(atPath: job.ipa.path, toFolder: extractDir.path) else {
            throw InjectorError("فشل فك ضغط ملف IPA")
        }
        let app = try findApp(in: extractDir)
        let infoURL = app.appendingPathComponent("Info.plist")
        let info = try readPlist(infoURL)
        guard let exeName = info["CFBundleExecutable"] as? String else {
            throw InjectorError("Info.plist لا يحتوي CFBundleExecutable")
        }
        let exeURL = app.appendingPathComponent(exeName)
        log("✅ التطبيق: \(app.lastPathComponent) — الملف التنفيذي: \(exeName)")

        // 2. Encryption check
        let mainBinary = try MachOBinary(url: exeURL)
        if mainBinary.isEncrypted {
            if job.options.skipEncryptionCheck {
                log("⚠️ الملف التنفيذي مشفّر (cryptid≠0)، تم تجاوز الفحص — غالباً لن يعمل التطبيق.")
            } else {
                throw InjectorError("ملف IPA مشفّر. استخدم نسخة مفكوكة التشفير (decrypted) أو فعّل «تجاوز فحص التشفير».")
            }
        }

        // 3. Collect tweaks
        var payload = TweakPayload()
        for (index, url) in job.tweaks.enumerated() {
            payload.merge(try collect(url, isExtra: false, scratch: work.appendingPathComponent("tweak\(index)")))
        }
        for (index, url) in job.extras.enumerated() {
            payload.merge(try collect(url, isExtra: true, scratch: work.appendingPathComponent("extra\(index)")))
        }
        guard !payload.injectables.isEmpty else {
            throw InjectorError("لم يُعثر على أي ملف dylib للحقن")
        }

        // 4. Copy into App.app/Frameworks
        let frameworksDir = app.appendingPathComponent("Frameworks", isDirectory: true)
        try fm.createDirectory(at: frameworksDir, withIntermediateDirectories: true)
        var copiedDylibs: [URL] = []
        var copiedFrameworks: [URL] = []
        for src in payload.injectables + payload.dependencies {
            let dst = frameworksDir.appendingPathComponent(src.lastPathComponent)
            try copyReplacing(src, to: dst)
            copiedDylibs.append(dst)
        }
        for src in payload.frameworks {
            let dst = frameworksDir.appendingPathComponent(src.lastPathComponent)
            try copyReplacing(src, to: dst)
            copiedFrameworks.append(dst)
        }
        for src in payload.bundles {
            try copyReplacing(src, to: app.appendingPathComponent(src.lastPathComponent))
            log("📁 نُسخ \(src.lastPathComponent) إلى جذر التطبيق")
        }
        log("📥 نُسخ \(copiedDylibs.count) dylib و \(copiedFrameworks.count) framework إلى Frameworks/")

        // 5. Fix paths inside the copied binaries
        let dylibNames = Set(copiedDylibs.map(\.lastPathComponent))
        let frameworkNames = Set(copiedFrameworks.map { $0.deletingPathExtension().lastPathComponent })
        var needsSubstrate = false
        for dylib in copiedDylibs {
            needsSubstrate = try fixPaths(of: dylib, idPath: "@rpath/\(dylib.lastPathComponent)",
                                          dylibNames: dylibNames, frameworkNames: frameworkNames,
                                          options: job.options) || needsSubstrate
        }
        for framework in copiedFrameworks {
            let name = framework.deletingPathExtension().lastPathComponent
            if name == "CydiaSubstrate" { continue }
            let binName = (try? readPlist(framework.appendingPathComponent("Info.plist")))?["CFBundleExecutable"] as? String ?? name
            let bin = framework.appendingPathComponent(binName)
            guard MachOBinary.isMachO(bin) else { continue }
            needsSubstrate = try fixPaths(of: bin, idPath: "@rpath/\(name).framework/\(binName)",
                                          dylibNames: dylibNames, frameworkNames: frameworkNames,
                                          options: job.options) || needsSubstrate
        }
        if needsSubstrate && !fm.fileExists(atPath: frameworksDir.appendingPathComponent("CydiaSubstrate.framework").path) {
            log("⚠️ الأداة تعتمد على CydiaSubstrate. أضف CydiaSubstrate.framework (مثل ElleKit) في «ملفات إضافية» وإلا سينهار التطبيق عند التشغيل.")
        }

        // 6. Inject load commands into the main executable
        if try mainBinary.addRpathIfNeeded("@executable_path/Frameworks") {
            log("➕ أُضيف LC_RPATH ‏@executable_path/Frameworks")
        }
        for dylib in payload.injectables {
            let loadPath = job.options.location.loadPath(for: dylib.lastPathComponent)
            if try mainBinary.injectDylib(loadPath, weak: job.options.weakInject) {
                log("💉 حُقن: \(loadPath)")
            } else {
                log("ℹ️ موجود مسبقاً: \(loadPath)")
            }
        }
        try mainBinary.save()

        // 7. App modifications
        try applyModifications(app: app, infoURL: infoURL, options: job.options)

        // 8. Signing (optional)
        let icon = job.icon?.path
        switch job.signing.mode {
        case .none:
            if job.icon != nil { log("⚠️ تغيير الأيقونة يحتاج توقيع (Fakesign أو شهادة) — تم تجاهله.") }
            log("ℹ️ بدون توقيع — يجب توقيع الملف قبل التثبيت.")
        case .adhoc:
            log("✍️ توقيع Fakesign (ad-hoc)…")
            if let error = ZSignBridge.signFolder(extractDir.path, p12Path: nil, password: nil,
                                                  provisionPath: nil, adhoc: true, iconPath: icon) {
                throw InjectorError("فشل التوقيع: \(error)")
            }
        case .certificate:
            guard let p12 = job.signing.p12, let provision = job.signing.provision else {
                throw InjectorError("اختر ملف الشهادة ‎.p12‎ وملف ‎.mobileprovision‎")
            }
            log("✍️ التوقيع بالشهادة \(p12.lastPathComponent)…")
            if let error = ZSignBridge.signFolder(extractDir.path, p12Path: p12.path, password: job.signing.password,
                                                  provisionPath: provision.path, adhoc: false, iconPath: icon) {
                throw InjectorError("فشل التوقيع: \(error)")
            }
        }

        // 9. Zip
        try fm.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let baseName = job.ipa.deletingPathExtension().lastPathComponent
        let suffix = job.signing.mode == .none ? "injected" : "injected_signed"
        let output = Self.outputDirectory.appendingPathComponent("\(baseName)_\(suffix).ipa")
        try? fm.removeItem(at: output)
        log("🗜️ ضغط الملف النهائي…")
        guard ZSignBridge.archiveFolder(extractDir.path, toZip: output.path, level: 6) else {
            throw InjectorError("فشل إنشاء ملف IPA النهائي")
        }
        log("🎉 تم: \(output.lastPathComponent)")
        return output
    }

    // MARK: - Steps

    private func findApp(in root: URL) throws -> URL {
        let payload = root.appendingPathComponent("Payload")
        let items = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
        guard let app = items.first(where: { $0.pathExtension == "app" }) else {
            throw InjectorError("لم يُعثر على Payload/*.app داخل الملف")
        }
        return app
    }

    private func collect(_ url: URL, isExtra: Bool, scratch: URL) throws -> TweakPayload {
        switch url.pathExtension.lowercased() {
        case "deb":
            log("📦 استخراج \(url.lastPathComponent)…")
            try TweakExtractor.extractDeb(url, to: scratch)
            var found = TweakExtractor.scan(scratch)
            if isExtra {
                found.dependencies += found.injectables
                found.injectables = []
            }
            log("   ↳ dylib للحقن: \(found.injectables.map(\.lastPathComponent).joined(separator: ", "))")
            return found
        case "dylib":
            guard MachOBinary.isMachO(url) else { throw InjectorError("\(url.lastPathComponent) ليس ملف Mach-O") }
            return isExtra ? TweakPayload(dependencies: [url]) : TweakPayload(injectables: [url])
        case "framework":
            return TweakPayload(frameworks: [url])
        case "bundle":
            return TweakPayload(bundles: [url])
        default:
            throw InjectorError("نوع ملف غير مدعوم: \(url.lastPathComponent)")
        }
    }

    /// Rewrites LC_ID_DYLIB, CydiaSubstrate and sibling-dylib paths. Returns true if the binary uses Substrate.
    private func fixPaths(of binary: URL, idPath: String, dylibNames: Set<String>,
                          frameworkNames: Set<String>, options: InjectOptions) throws -> Bool {
        let macho = try MachOBinary(url: binary)
        let usesSubstrate = macho.linkedLibraries.contains {
            Self.substrateNames.contains(($0 as NSString).lastPathComponent)
        }
        let result = macho.rewriteDylibPaths { path, isID in
            if isID { return idPath }
            let base = (path as NSString).lastPathComponent
            if options.fixSubstratePaths && Self.substrateNames.contains(base) {
                return Self.substrateLoadPath
            }
            if path.hasPrefix("@") { return nil }
            if dylibNames.contains(base) { return "@rpath/\(base)" }
            if let range = path.range(of: ".framework/") {
                let fwName = (String(path[..<range.lowerBound]) as NSString).lastPathComponent
                if frameworkNames.contains(fwName) {
                    return "@rpath/\(fwName).framework/" + String(path[range.upperBound...])
                }
            }
            return nil
        }
        for line in result.changed { log("🔧 \(binary.lastPathComponent): \(line)") }
        for path in result.failed { log("⚠️ \(binary.lastPathComponent): تعذّر تعديل المسار \(path) (لا توجد مساحة)") }
        if !result.changed.isEmpty { try macho.save() }
        return usesSubstrate
    }

    private func applyModifications(app: URL, infoURL: URL, options: InjectOptions) throws {
        let loaded = try readPlistWithFormat(infoURL)
        var info = loaded.0
        let format = loaded.1
        let oldBundleID = info["CFBundleIdentifier"] as? String ?? ""
        let newBundleID = options.bundleID.trimmingCharacters(in: .whitespaces)
        let newName = options.displayName.trimmingCharacters(in: .whitespaces)
        let newVersion = options.version.trimmingCharacters(in: .whitespaces)

        if !newBundleID.isEmpty {
            info["CFBundleIdentifier"] = newBundleID
            log("🆔 Bundle ID: \(oldBundleID) → \(newBundleID)")
        }
        if !newName.isEmpty {
            info["CFBundleDisplayName"] = newName
            info["CFBundleName"] = newName
            log("🏷️ الاسم: \(newName)")
        }
        if !newVersion.isEmpty {
            info["CFBundleShortVersionString"] = newVersion
            log("🔢 الإصدار: \(newVersion)")
        }
        if options.removeURLSchemes, info.removeValue(forKey: "CFBundleURLTypes") != nil {
            log("🗑️ حُذفت URL Schemes")
        }
        if options.enableDocumentBrowser {
            info["UISupportsDocumentBrowser"] = true
            info["UIFileSharingEnabled"] = true
            info["LSSupportsOpeningDocumentsInPlace"] = true
            log("📂 فُعّل Document Browser")
        }
        if options.removeSupportedDevices, info.removeValue(forKey: "UISupportedDevices") != nil {
            log("🗑️ حُذف UISupportedDevices")
        }
        try writePlist(info, format: format, to: infoURL)

        if options.removeExtensions {
            for name in ["PlugIns", "Extensions"] {
                let dir = app.appendingPathComponent(name)
                if fm.fileExists(atPath: dir.path) {
                    try fm.removeItem(at: dir)
                    log("🗑️ حُذف \(name)/")
                }
            }
        }
        if options.removeWatchApp {
            for name in ["Watch", "com.apple.WatchPlaceholder"] {
                let dir = app.appendingPathComponent(name)
                if fm.fileExists(atPath: dir.path) {
                    try fm.removeItem(at: dir)
                    log("🗑️ حُذف \(name)/")
                }
            }
        }

        // Keep nested bundle IDs prefixed by the new main ID.
        if !newBundleID.isEmpty, !oldBundleID.isEmpty {
            for name in ["PlugIns", "Extensions", "Watch"] {
                let dir = app.appendingPathComponent(name)
                guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
                for case let url as URL in walker where url.lastPathComponent == "Info.plist" {
                    guard let loaded = try? readPlistWithFormat(url) else { continue }
                    var sub = loaded.0
                    let subFormat = loaded.1
                    var changed = false
                    for key in ["CFBundleIdentifier", "WKCompanionAppBundleIdentifier"] {
                        if let value = sub[key] as? String, value.hasPrefix(oldBundleID) {
                            sub[key] = newBundleID + String(value.dropFirst(oldBundleID.count))
                            changed = true
                        }
                    }
                    if changed { try writePlist(sub, format: subFormat, to: url) }
                }
            }
        }
    }

    // MARK: - Helpers

    private func copyReplacing(_ src: URL, to dst: URL) throws {
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.copyItem(at: src, to: dst)
    }

    private func readPlist(_ url: URL) throws -> [String: Any] {
        try readPlistWithFormat(url).0
    }

    private func readPlistWithFormat(_ url: URL) throws -> ([String: Any], PropertyListSerialization.PropertyListFormat) {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            throw InjectorError("تعذّرت قراءة \(url.lastPathComponent)")
        }
        return (dict, format)
    }

    private func writePlist(_ dict: [String: Any], format: PropertyListSerialization.PropertyListFormat, to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
        try data.write(to: url)
    }
}
