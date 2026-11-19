import Foundation
import UniformTypeIdentifiers

enum ImportTarget: Identifiable {
    case ipa, tweak, extra, icon, p12, provision

    var id: Self { self }

    var allowsMultiple: Bool { self == .tweak || self == .extra }

    var contentTypes: [UTType] {
        switch self {
        case .icon: return [.png]
        case .extra: return [.item, .folder]
        default: return [.item]
        }
    }

    var allowedExtensions: Set<String> {
        switch self {
        case .ipa: return ["ipa", "tipa"]
        case .tweak: return ["dylib", "deb"]
        case .extra: return ["dylib", "deb", "framework", "bundle"]
        case .icon: return ["png"]
        case .p12: return ["p12", "pfx"]
        case .provision: return ["mobileprovision"]
        }
    }
}

@MainActor
final class InjectorViewModel: ObservableObject {
    @Published var ipa: URL?
    @Published var tweaks: [URL] = []
    @Published var extras: [URL] = []
    @Published var icon: URL?
    @Published var options = InjectOptions()
    @Published var signing = SigningConfig()

    @Published var preparing: ImportTarget?
    @Published var isRunning = false
    @Published var logLines: [String] = []
    @Published var result: InjectionResult?
    @Published var errorMessage: String?

    enum InstallState: Equatable {
        case idle, preparing, waiting, downloading, finished
    }
    @Published var installState: InstallState = .idle
    @Published var autoInstall = true

    var output: URL? { result?.url }

    /// OTA install is only possible for IPAs signed with a real certificate.
    var canInstall: Bool { result?.signedWithCertificate == true }

    private let inputsDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Inputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A job with no tweaks is a sign-only / install-only job (still valid).
    var isSignOnly: Bool { tweaks.isEmpty && extras.isEmpty }

    var canStart: Bool {
        guard ipa != nil, !isRunning, preparing == nil else { return false }
        if signing.mode == .certificate {
            return signing.p12 != nil && signing.provision != nil
        }
        return true
    }

    var missingRequirement: String? {
        if ipa == nil { return "اختر ملف IPA" }
        if signing.mode == .certificate {
            if signing.p12 == nil { return "اختر ملف الشهادة ‎.p12‎" }
            if signing.provision == nil { return "اختر ملف ‎.mobileprovision‎" }
        }
        return nil
    }

    /// Label for the main action button (inject vs. sign-only).
    var actionTitle: String { isSignOnly ? "توقيع وتثبيت" : "ابدأ الحقن" }

    var lastLog: String? { logLines.last }

    // MARK: - Picking

    func pick(_ target: ImportTarget) {
        guard preparing == nil, !isRunning else { return }
        DocumentPicker.shared.present(types: target.contentTypes, allowsMultiple: target.allowsMultiple) { [weak self] urls in
            Task { @MainActor in self?.receive(urls, for: target) }
        }
    }

    /// Adds a dylib/deb downloaded from the library to the tweaks list.
    func addTweakFile(_ url: URL) {
        receive([url], for: .tweak)
    }

    private func receive(_ urls: [URL], for target: ImportTarget) {
        let accepted = urls.filter { target.allowedExtensions.contains($0.pathExtension.lowercased()) }
        let rejected = urls.filter { !accepted.contains($0) }
        if !rejected.isEmpty {
            errorMessage = "ملف غير مناسب: \(rejected.map(\.lastPathComponent).joined(separator: "، "))\nالمسموح: \(target.allowedExtensions.sorted().joined(separator: ", "))"
        }
        guard !accepted.isEmpty else { return }

        preparing = target
        let dir = inputsDir
        Task.detached(priority: .userInitiated) {
            var stored: [URL] = []
            var failure: String?
            for url in accepted {
                do { stored.append(try Self.store(url, in: dir)) } catch {
                    failure = "تعذّر تجهيز \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.preparing = nil
                if let failure { self.errorMessage = failure }
                for local in stored { self.assign(local, to: target) }
            }
        }
    }

    private func assign(_ url: URL, to target: ImportTarget) {
        switch target {
        case .ipa: ipa = url; result = nil
        case .tweak: if !tweaks.contains(where: { $0.lastPathComponent == url.lastPathComponent }) { tweaks.append(url) }
        case .extra: if !extras.contains(where: { $0.lastPathComponent == url.lastPathComponent }) { extras.append(url) }
        case .icon: icon = url
        case .p12: signing.p12 = url
        case .provision: signing.provision = url
        }
    }

    /// Moves the picker's copy into our own Inputs folder (falls back to copying).
    nonisolated private static func store(_ url: URL, in dir: URL) throws -> URL {
        let fm = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = dir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try fm.moveItem(at: url, to: destination)
        } catch {
            try fm.copyItem(at: url, to: destination)
        }
        return destination
    }

    func remove(_ url: URL) {
        tweaks.removeAll { $0 == url }
        extras.removeAll { $0 == url }
        if ipa == url { ipa = nil }
        if icon == url { icon = nil }
        if signing.p12 == url { signing.p12 = nil }
        if signing.provision == url { signing.provision = nil }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Run

    func start() {
        guard let ipa, canStart else { return }
        let job = InjectionJob(ipa: ipa, tweaks: tweaks, extras: extras, icon: icon,
                               options: options, signing: signing)
        isRunning = true
        result = nil
        logLines = []
        stopInstall()

        // Large stack: zsign uses big buffers and deep recursion when walking the bundle.
        let thread = Thread { [weak self] in
            let injector = Injector { line in
                Task { @MainActor in self?.logLines.append(line) }
            }
            do {
                let result = try injector.run(job)
                Task { @MainActor in self?.finish(result: result, error: nil) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in self?.finish(result: nil, error: message) }
            }
        }
        thread.stackSize = 16 * 1024 * 1024
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func finish(result: InjectionResult?, error: String?) {
        if let error {
            logLines.append("❌ \(error)")
            errorMessage = error
        }
        self.result = result
        isRunning = false
        if autoInstall, canInstall {
            install()
        }
    }

    // MARK: - Install on this device

    func install() {
        guard let result, canInstall, installState == .idle || installState == .finished else { return }
        let installer = LocalInstaller.shared
        installer.onEvent = { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .started: self.installState = .waiting
                case .downloading: self.installState = .downloading
                case .finishedServing:
                    self.installState = .finished
                    self.logLines.append("📲 اكتمل إرسال الملف — تابع التثبيت على الشاشة الرئيسية")
                case .stopped:
                    if self.installState != .finished { self.installState = .idle }
                }
            }
        }
        installState = .preparing
        logLines.append("📲 بدء التثبيت على الجهاز…")
        Task {
            do {
                try await installer.install(result)
            } catch {
                installState = .idle
                errorMessage = "تعذّر بدء التثبيت: \(error.localizedDescription)"
                logLines.append("❌ \(error.localizedDescription)")
            }
        }
    }

    func stopInstall() {
        LocalInstaller.shared.stop()
        installState = .idle
    }

    func reset() {
        guard !isRunning else { return }
        ipa = nil
        tweaks = []
        extras = []
        icon = nil
        signing.p12 = nil
        signing.provision = nil
        signing.password = ""
        result = nil
        stopInstall()
        logLines = []
        try? FileManager.default.removeItem(at: inputsDir)
        try? FileManager.default.createDirectory(at: inputsDir, withIntermediateDirectories: true)
    }

    nonisolated static func sizeText(_ url: URL) -> String {
        var size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if size == nil, let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            size = attributes[.size] as? Int
        }
        guard let size, size > 0 else { return url.pathExtension.uppercased() }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
