import Foundation

/// Minimal Mach-O editor: reads thin or FAT binaries and edits their load commands in place.
/// Used to inject LC_LOAD_DYLIB, add LC_RPATH and rewrite dylib paths (e.g. CydiaSubstrate).
final class MachOBinary {
    static let LC_SEGMENT: UInt32 = 0x1
    static let LC_LOAD_DYLIB: UInt32 = 0xC
    static let LC_ID_DYLIB: UInt32 = 0xD
    static let LC_SEGMENT_64: UInt32 = 0x19
    static let LC_LAZY_LOAD_DYLIB: UInt32 = 0x20
    static let LC_ENCRYPTION_INFO: UInt32 = 0x21
    static let LC_ENCRYPTION_INFO_64: UInt32 = 0x2C
    static let LC_LOAD_WEAK_DYLIB: UInt32 = 0x8000_0018
    static let LC_RPATH: UInt32 = 0x8000_001C
    static let LC_REEXPORT_DYLIB: UInt32 = 0x8000_001F
    static let LC_LOAD_UPWARD_DYLIB: UInt32 = 0x8000_0023

    static let dylibCommands: Set<UInt32> = [
        LC_LOAD_DYLIB, LC_ID_DYLIB, LC_LOAD_WEAK_DYLIB,
        LC_REEXPORT_DYLIB, LC_LAZY_LOAD_DYLIB, LC_LOAD_UPWARD_DYLIB,
    ]

    struct Slice {
        let offset: Int
        let size: Int
        let is64: Bool
        var headerSize: Int { is64 ? 32 : 28 }
    }

    struct Command {
        let offset: Int
        let cmd: UInt32
        let size: Int
    }

    let url: URL
    private(set) var bytes: [UInt8]
    private(set) var slices: [Slice] = []

    init(url: URL) throws {
        self.url = url
        bytes = [UInt8](try Data(contentsOf: url))
        slices = try parseSlices()
    }

    /// Quick magic check without loading the whole file.
    static func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let b = [UInt8](handle.readData(ofLength: 4))
        guard b.count == 4 else { return false }
        let le = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        return [0xFEED_FACE, 0xFEED_FACF, 0xBEBA_FECA, 0xBFBA_FECA].contains(le)
    }

    /// Writes the edited bytes back, keeping the original POSIX permissions (executable bit).
    func save() throws {
        let fm = FileManager.default
        let perms = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions]
        try Data(bytes).write(to: url)
        if let perms {
            try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: url.path)
        }
    }

    // MARK: - Queries

    var isEncrypted: Bool {
        for s in slices {
            for c in commands(s) where c.cmd == Self.LC_ENCRYPTION_INFO || c.cmd == Self.LC_ENCRYPTION_INFO_64 {
                if c.size >= 20, le32(c.offset + 16) != 0 { return true }
            }
        }
        return false
    }

    /// Libraries this binary links against (first slice).
    var linkedLibraries: [String] {
        guard let s = slices.first else { return [] }
        return commands(s)
            .filter { Self.dylibCommands.contains($0.cmd) && $0.cmd != Self.LC_ID_DYLIB }
            .map { pathString($0) }
    }

    // MARK: - Edits

    /// Adds LC_LOAD_DYLIB (or LC_LOAD_WEAK_DYLIB) to every slice. Returns false if it was already present.
    @discardableResult
    func injectDylib(_ path: String, weak: Bool) throws -> Bool {
        var changed = false
        for s in slices {
            let exists = commands(s).contains {
                ($0.cmd == Self.LC_LOAD_DYLIB || $0.cmd == Self.LC_LOAD_WEAK_DYLIB) && pathString($0) == path
            }
            if exists { continue }
            let cmd = weak ? Self.LC_LOAD_WEAK_DYLIB : Self.LC_LOAD_DYLIB
            try append(Self.dylibCommand(path, cmd: cmd), to: s)
            changed = true
        }
        return changed
    }

    /// Adds LC_RPATH to every slice that does not have it yet.
    @discardableResult
    func addRpathIfNeeded(_ path: String) throws -> Bool {
        var changed = false
        for s in slices {
            let exists = commands(s).contains { $0.cmd == Self.LC_RPATH && pathString($0) == path }
            if exists { continue }
            try append(Self.rpathCommand(path), to: s)
            changed = true
        }
        return changed
    }

    /// Rewrites dylib paths in place. `transform(path, isID)` returns the new path, or nil to keep it.
    /// The new path must fit in the existing command; otherwise it is reported in `failed`.
    func rewriteDylibPaths(_ transform: (_ path: String, _ isID: Bool) -> String?) -> (changed: [String], failed: [String]) {
        var changed = Set<String>()
        var failed = Set<String>()
        for s in slices {
            for c in commands(s) where Self.dylibCommands.contains(c.cmd) {
                let old = pathString(c)
                guard let new = transform(old, c.cmd == Self.LC_ID_DYLIB), new != old else { continue }
                let nameOffset = Int(le32(c.offset + 8))
                guard nameOffset >= 24, nameOffset < c.size else { failed.insert(old); continue }
                let start = c.offset + nameOffset
                let capacity = c.size - nameOffset
                let newBytes = Array(new.utf8)
                if newBytes.count + 1 <= capacity {
                    var replacement = newBytes
                    replacement.append(contentsOf: [UInt8](repeating: 0, count: capacity - newBytes.count))
                    bytes.replaceSubrange(start..<(start + capacity), with: replacement)
                    changed.insert("\(old) → \(new)")
                } else {
                    failed.insert(old)
                }
            }
        }
        return (Array(changed).sorted(), Array(failed).sorted())
    }

    // MARK: - Parsing

    private func parseSlices() throws -> [Slice] {
        guard bytes.count >= 32 else { throw invalid() }
        let magic = be32(0)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {
            let fat64 = magic == 0xCAFE_BABF
            let count = Int(be32(4))
            let entrySize = fat64 ? 32 : 20
            guard count > 0, count < 32, 8 + count * entrySize <= bytes.count else { throw invalid() }
            var result: [Slice] = []
            for i in 0..<count {
                let e = 8 + i * entrySize
                let off = fat64 ? Int(truncatingIfNeeded: be64(e + 8)) : Int(be32(e + 8))
                let size = fat64 ? Int(truncatingIfNeeded: be64(e + 16)) : Int(be32(e + 12))
                result.append(try thinSlice(at: off, size: size))
            }
            return result
        }
        return [try thinSlice(at: 0, size: bytes.count)]
    }

    private func thinSlice(at offset: Int, size: Int) throws -> Slice {
        guard offset >= 0, size > 32, offset + size <= bytes.count else { throw invalid() }
        let magic = le32(offset)
        guard magic == 0xFEED_FACF || magic == 0xFEED_FACE else { throw invalid() }
        let slice = Slice(offset: offset, size: size, is64: magic == 0xFEED_FACF)
        let sizeofcmds = Int(le32(offset + 20))
        guard slice.headerSize + sizeofcmds <= size else { throw invalid() }
        return slice
    }

    func commands(_ s: Slice) -> [Command] {
        let count = Int(le32(s.offset + 16))
        var p = s.offset + s.headerSize
        let end = p + Int(le32(s.offset + 20))
        var result: [Command] = []
        for _ in 0..<count {
            guard p + 8 <= end else { break }
            let size = Int(le32(p + 4))
            guard size >= 8, p + size <= end else { break }
            result.append(Command(offset: p, cmd: le32(p), size: size))
            p += size
        }
        return result
    }

    /// Path string of dylib_command / rpath_command (both keep the string offset at +8).
    private func pathString(_ c: Command) -> String {
        guard c.size >= 12 else { return "" }
        let nameOffset = Int(le32(c.offset + 8))
        guard nameOffset < c.size else { return "" }
        let limit = c.offset + c.size
        var e = c.offset + nameOffset
        let start = e
        while e < limit && bytes[e] != 0 { e += 1 }
        return String(decoding: bytes[start..<e], as: UTF8.self)
    }

    /// File offset (relative to the slice) where the first section/segment data begins.
    /// New load commands must end before this point.
    private func firstDataOffset(_ s: Slice) -> Int {
        var minOffset = s.size
        let zerofill: Set<UInt32> = [0x1, 0xC, 0x12]
        for c in commands(s) {
            if c.cmd == Self.LC_SEGMENT_64, c.size >= 72 {
                let fileoff = Int(truncatingIfNeeded: le64(c.offset + 40))
                let filesize = Int(truncatingIfNeeded: le64(c.offset + 48))
                if fileoff > 0 && filesize > 0 { minOffset = min(minOffset, fileoff) }
                let nsects = Int(le32(c.offset + 64))
                for i in 0..<nsects {
                    let sec = c.offset + 72 + i * 80
                    guard sec + 80 <= c.offset + c.size else { break }
                    let off = Int(le32(sec + 48))
                    if off > 0 && !zerofill.contains(le32(sec + 64) & 0xFF) { minOffset = min(minOffset, off) }
                }
            } else if c.cmd == Self.LC_SEGMENT, c.size >= 56 {
                let fileoff = Int(le32(c.offset + 32))
                let filesize = Int(le32(c.offset + 36))
                if fileoff > 0 && filesize > 0 { minOffset = min(minOffset, fileoff) }
                let nsects = Int(le32(c.offset + 48))
                for i in 0..<nsects {
                    let sec = c.offset + 56 + i * 68
                    guard sec + 68 <= c.offset + c.size else { break }
                    let off = Int(le32(sec + 40))
                    if off > 0 && !zerofill.contains(le32(sec + 56) & 0xFF) { minOffset = min(minOffset, off) }
                }
            }
        }
        return minOffset
    }

    private func append(_ payload: [UInt8], to s: Slice) throws {
        let sizeofcmds = Int(le32(s.offset + 20))
        let start = s.offset + s.headerSize + sizeofcmds
        let limit = s.offset + firstDataOffset(s)
        let end = start + payload.count
        guard end <= limit, bytes[start..<end].allSatisfy({ $0 == 0 }) else {
            throw InjectorError("لا توجد مساحة كافية في رأس الملف لإضافة أمر تحميل: \(url.lastPathComponent)")
        }
        bytes.replaceSubrange(start..<end, with: payload)
        put32(le32(s.offset + 16) + 1, at: s.offset + 16)
        put32(UInt32(sizeofcmds + payload.count), at: s.offset + 20)
    }

    // MARK: - Builders

    private static func dylibCommand(_ path: String, cmd: UInt32) -> [UInt8] {
        let pathBytes = Array(path.utf8)
        let size = (24 + pathBytes.count + 1 + 7) & ~7
        var b: [UInt8] = []
        b.append(contentsOf: le(cmd))
        b.append(contentsOf: le(UInt32(size)))
        b.append(contentsOf: le(24))          // name.offset
        b.append(contentsOf: le(2))           // timestamp
        b.append(contentsOf: le(0x0001_0000)) // current_version 1.0.0
        b.append(contentsOf: le(0x0001_0000)) // compatibility_version 1.0.0
        b.append(contentsOf: pathBytes)
        b.append(contentsOf: [UInt8](repeating: 0, count: size - b.count))
        return b
    }

    private static func rpathCommand(_ path: String) -> [UInt8] {
        let pathBytes = Array(path.utf8)
        let size = (12 + pathBytes.count + 1 + 7) & ~7
        var b: [UInt8] = []
        b.append(contentsOf: le(LC_RPATH))
        b.append(contentsOf: le(UInt32(size)))
        b.append(contentsOf: le(12))
        b.append(contentsOf: pathBytes)
        b.append(contentsOf: [UInt8](repeating: 0, count: size - b.count))
        return b
    }

    // MARK: - Byte helpers

    private static func le(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    private func le32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
    }

    private func le64(_ o: Int) -> UInt64 { UInt64(le32(o)) | UInt64(le32(o + 4)) << 32 }

    private func be32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[o]) << 24 | UInt32(bytes[o + 1]) << 16 | UInt32(bytes[o + 2]) << 8 | UInt32(bytes[o + 3])
    }

    private func be64(_ o: Int) -> UInt64 { UInt64(be32(o)) << 32 | UInt64(be32(o + 4)) }

    private func put32(_ v: UInt32, at o: Int) {
        bytes.replaceSubrange(o..<(o + 4), with: Self.le(v))
    }

    private func invalid() -> InjectorError {
        InjectorError("ملف Mach-O غير صالح: \(url.lastPathComponent)")
    }
}
