import Foundation
import Security

/// A saved signing certificate: the .p12 and .mobileprovision files plus a name.
/// The password is kept in the Keychain, never in the metadata file.
struct SavedCertificate: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var p12Name: String
    var provisionName: String
    var addedAt: Date

    /// Folder holding this certificate's two files.
    func folder(in root: URL) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func p12URL(in root: URL) -> URL { folder(in: root).appendingPathComponent(p12Name) }
    func provisionURL(in root: URL) -> URL { folder(in: root).appendingPathComponent(provisionName) }
}

/// Stores certificates in Application Support and remembers the selected one.
@MainActor
final class CertificateStore: ObservableObject {
    @Published private(set) var certificates: [SavedCertificate] = []
    @Published var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedCertificateID") }
    }

    private let root: URL
    private let metadataURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Certificates", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base
        metadataURL = base.appendingPathComponent("certificates.json")
        load()
        selectedID = UserDefaults.standard.string(forKey: "selectedCertificateID")
        if selectedID == nil { selectedID = certificates.first?.id }
    }

    var selected: SavedCertificate? {
        certificates.first { $0.id == selectedID }
    }

    // MARK: - CRUD

    /// Copies the two files into storage, saves the password in Keychain, and selects the new cert.
    @discardableResult
    func add(name: String, p12: URL, provision: URL, password: String) throws -> SavedCertificate {
        let id = UUID().uuidString
        let cert = SavedCertificate(
            id: id,
            name: name.isEmpty ? defaultName() : name,
            p12Name: p12.lastPathComponent,
            provisionName: provision.lastPathComponent,
            addedAt: Date()
        )
        let folder = cert.folder(in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try copy(p12, to: cert.p12URL(in: root))
        try copy(provision, to: cert.provisionURL(in: root))
        Keychain.set(password, for: id)

        certificates.append(cert)
        persist()
        selectedID = id
        return cert
    }

    func rename(_ cert: SavedCertificate, to newName: String) {
        guard let index = certificates.firstIndex(of: cert), !newName.isEmpty else { return }
        certificates[index].name = newName
        persist()
    }

    func delete(_ cert: SavedCertificate) {
        try? FileManager.default.removeItem(at: cert.folder(in: root))
        Keychain.delete(for: cert.id)
        certificates.removeAll { $0.id == cert.id }
        persist()
        if selectedID == cert.id { selectedID = certificates.first?.id }
    }

    func password(for cert: SavedCertificate) -> String { Keychain.get(cert.id) ?? "" }
    func p12URL(for cert: SavedCertificate) -> URL { cert.p12URL(in: root) }
    func provisionURL(for cert: SavedCertificate) -> URL { cert.provisionURL(in: root) }

    func files(for cert: SavedCertificate) -> (p12: URL, provision: URL, password: String) {
        (p12URL(for: cert), provisionURL(for: cert), password(for: cert))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let saved = try? JSONDecoder().decode([SavedCertificate].self, from: data) else { return }
        certificates = saved.sorted { $0.addedAt < $1.addedAt }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(certificates) {
            try? data.write(to: metadataURL)
        }
    }

    private func copy(_ src: URL, to dst: URL) throws {
        if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
        try FileManager.default.copyItem(at: src, to: dst)
    }

    private func defaultName() -> String {
        "شهادة \(certificates.count + 1)"
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.dylibsign.certificates"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
