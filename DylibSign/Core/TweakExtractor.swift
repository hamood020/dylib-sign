import Foundation

/// What a tweak (deb / dylib / framework) contributes to the app.
struct TweakPayload {
    /// Dylibs that get an LC_LOAD_DYLIB in the main executable.
    var injectables: [URL] = []
    /// Dylibs copied into Frameworks only (dependencies of the tweak).
    var dependencies: [URL] = []
    var frameworks: [URL] = []
    var bundles: [URL] = []

    mutating func merge(_ other: TweakPayload) {
        injectables += other.injectables
        dependencies += other.dependencies
        frameworks += other.frameworks
        bundles += other.bundles
    }
}

enum TweakExtractor {
    /// Extracts the data archive of a .deb (ar + tar[.xz|.gz]) into `destination`.
    static func extractDeb(_ deb: URL, to destination: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: deb))
        guard bytes.count > 8, String(decoding: bytes[0..<8], as: UTF8.self) == "!<arch>\n" else {
            throw InjectorError("ملف deb غير صالح: \(deb.lastPathComponent)")
        }

        var p = 8
        while p + 60 <= bytes.count {
            let rawName = String(decoding: bytes[p..<(p + 16)], as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)
            let name = rawName.hasSuffix("/") ? String(rawName.dropLast()) : rawName
            let sizeText = String(decoding: bytes[(p + 48)..<(p + 58)], as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)
            guard let size = Int(sizeText), size >= 0, p + 60 + size <= bytes.count else {
                throw InjectorError("ملف deb تالف: \(deb.lastPathComponent)")
            }
            let body = Data(bytes[(p + 60)..<(p + 60 + size)])

            if name.hasPrefix("data.tar") {
                let tar = try decompress(body, member: name)
                try untar([UInt8](tar), to: destination)
                return
            }
            p += 60 + size
            if p % 2 == 1 { p += 1 }
        }
        throw InjectorError("لم يُعثر على data.tar داخل \(deb.lastPathComponent)")
    }

    /// Scans an extracted deb (or any folder) for injectable content.
    static func scan(_ root: URL) -> TweakPayload {
        let fm = FileManager.default
        var dylibs: [URL] = []
        var payload = TweakPayload()
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return payload
        }
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            switch url.pathExtension.lowercased() {
            case "framework":
                payload.frameworks.append(url)
                walker.skipDescendants()
            case "bundle":
                payload.bundles.append(url)
                walker.skipDescendants()
            case "dylib":
                if values?.isDirectory != true, MachOBinary.isMachO(url) { dylibs.append(url) }
            default:
                break
            }
        }

        // Tweaks live in DynamicLibraries / TweakInject; anything else (usr/lib…) is a dependency.
        let tweakDirs = ["/DynamicLibraries/", "/TweakInject/"]
        let tweaks = dylibs.filter { url in tweakDirs.contains { url.path.contains($0) } }
        if tweaks.isEmpty {
            payload.injectables = dylibs
        } else {
            payload.injectables = tweaks
            payload.dependencies = dylibs.filter { !tweaks.contains($0) }
        }
        return payload
    }

    // MARK: - Decompression

    private static func decompress(_ data: Data, member: String) throws -> Data {
        do {
            if member.hasSuffix(".xz") {
                return try (data as NSData).decompressed(using: .lzma) as Data
            }
            if member.hasSuffix(".gz") {
                return try gunzip(data)
            }
        } catch let error as InjectorError {
            throw error
        } catch {
            throw InjectorError("فشل فك ضغط \(member): \(error.localizedDescription)")
        }
        if member == "data.tar" { return data }
        throw InjectorError("صيغة الضغط \(member) غير مدعومة (المدعوم: xz و gz). استخرج الـ dylib يدوياً وأضفه.")
    }

    private static func gunzip(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else {
            throw InjectorError("ملف gzip غير صالح")
        }
        let flags = b[3]
        var p = 10
        if flags & 0x04 != 0 { p += 2 + (Int(b[p]) | Int(b[p + 1]) << 8) } // FEXTRA
        if flags & 0x08 != 0 { while p < b.count && b[p] != 0 { p += 1 }; p += 1 } // FNAME
        if flags & 0x10 != 0 { while p < b.count && b[p] != 0 { p += 1 }; p += 1 } // FCOMMENT
        if flags & 0x02 != 0 { p += 2 } // FHCRC
        guard p < b.count - 8 else { throw InjectorError("ملف gzip تالف") }
        // NSData .zlib is raw DEFLATE, which is exactly the gzip body.
        return try (Data(b[p..<(b.count - 8)]) as NSData).decompressed(using: .zlib) as Data
    }

    // MARK: - Tar

    private static func untar(_ tar: [UInt8], to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var p = 0
        var longName: String?

        func field(_ start: Int, _ length: Int) -> ArraySlice<UInt8> {
            tar[(p + start)..<(p + start + length)]
        }
        func cString(_ s: ArraySlice<UInt8>) -> String {
            String(decoding: s.prefix { $0 != 0 }, as: UTF8.self)
        }
        func octal(_ s: ArraySlice<UInt8>) -> Int {
            if let first = s.first, first & 0x80 != 0 { // GNU base-256
                var value = 0
                for (i, byte) in s.enumerated() { value = (value << 8) | Int(i == 0 ? byte & 0x7F : byte) }
                return value
            }
            let text = cString(s).trimmingCharacters(in: .whitespaces)
            return Int(text, radix: 8) ?? 0
        }

        while p + 512 <= tar.count {
            if field(0, 512).allSatisfy({ $0 == 0 }) { break }
            var name = cString(field(0, 100))
            let isUstar = cString(field(257, 5)) == "ustar"
            if isUstar {
                let prefix = cString(field(345, 155))
                if !prefix.isEmpty { name = prefix + "/" + name }
            }
            if let long = longName { name = long; longName = nil }
            let size = octal(field(124, 12))
            let type = tar[p + 156]
            let dataStart = p + 512
            guard size >= 0, dataStart + size <= tar.count else { throw InjectorError("أرشيف tar تالف داخل الـ deb") }

            switch type {
            case UInt8(ascii: "L"):
                longName = cString(tar[dataStart..<(dataStart + size)])
            case 0, UInt8(ascii: "0"), UInt8(ascii: "7"):
                if let rel = safeRelativePath(name) {
                    let out = destination.appendingPathComponent(rel)
                    try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(tar[dataStart..<(dataStart + size)]).write(to: out)
                }
            case UInt8(ascii: "5"):
                if let rel = safeRelativePath(name) {
                    try fm.createDirectory(at: destination.appendingPathComponent(rel), withIntermediateDirectories: true)
                }
            default:
                break // symlinks, hardlinks, pax headers: not needed for tweaks
            }
            p = dataStart + ((size + 511) / 512) * 512
        }
    }

    /// Rejects absolute or parent-escaping paths from untrusted archives.
    private static func safeRelativePath(_ raw: String) -> String? {
        let parts = raw.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        return parts.joined(separator: "/")
    }
}
