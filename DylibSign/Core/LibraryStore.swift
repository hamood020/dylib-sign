import Foundation

/// One entry of library/index.json in the GitHub repo.
struct LibraryDylib: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    var description: String?
    var activation: String?
    let file: String
    var version: String?
    var author: String?
    var category: String?
    var icon: String?
    var needsSubstrate: Bool?
}

private struct LibraryIndex: Codable {
    var dylibs: [LibraryDylib]
}

/// Loads the dylib catalog from the repo (with an offline cache) and downloads entries.
@MainActor
final class LibraryStore: ObservableObject {
    static let baseURL = URL(string: "https://raw.githubusercontent.com/hamood020/dylib-sign/main/library/")!
    static let indexURL = baseURL.appendingPathComponent("index.json")

    enum State: Equatable {
        case idle, loading, loaded, failed(String)
    }

    @Published private(set) var items: [LibraryDylib] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var downloading: Set<String> = []
    @Published var isOffline = false

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("library-index.json")
    }

    init() {
        if let data = try? Data(contentsOf: cacheURL), let index = try? JSONDecoder().decode(LibraryIndex.self, from: data) {
            items = index.dylibs
        }
    }

    func load() async {
        state = .loading
        do {
            var request = URLRequest(url: Self.indexURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw InjectorError("تعذّر تحميل المكتبة (رمز \(http.statusCode))")
            }
            let index: LibraryIndex
            do {
                index = try JSONDecoder().decode(LibraryIndex.self, from: data)
            } catch {
                throw InjectorError("ملف المكتبة index.json غير صالح")
            }
            items = index.dylibs
            isOffline = false
            try? data.write(to: cacheURL)
            state = .loaded
        } catch {
            isOffline = !items.isEmpty
            state = items.isEmpty ? .failed(error.localizedDescription) : .loaded
        }
    }

    func fileURL(for item: LibraryDylib) -> URL? {
        if item.file.lowercased().hasPrefix("http") {
            return URL(string: item.file)
        }
        let encoded = item.file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.file
        return URL(string: encoded, relativeTo: Self.baseURL)?.absoluteURL
    }

    /// Downloads the dylib/deb and returns a local file with the original name.
    func download(_ item: LibraryDylib) async throws -> URL {
        guard let remote = fileURL(for: item) else { throw InjectorError("رابط الملف غير صالح: \(item.file)") }
        downloading.insert(item.id)
        defer { downloading.remove(item.id) }

        let (temp, response) = try await URLSession.shared.download(from: remote)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InjectorError("تعذّر تحميل \(item.name) (رمز \(http.statusCode))")
        }

        var name = remote.lastPathComponent.removingPercentEncoding ?? remote.lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        if ext != "dylib" && ext != "deb" { name = "\(item.id).dylib" }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryDownloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }
}
