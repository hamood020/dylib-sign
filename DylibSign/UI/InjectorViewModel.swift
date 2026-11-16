import Foundation
import UniformTypeIdentifiers

enum ImportTarget: Identifiable {
    case ipa, tweak, extra, icon, p12, provision

    var id: Self { self }

    var allowsMultiple: Bool { self == .tweak || self == .extra }

    var contentTypes: [UTType] {
        switch self {
        case .icon: return [.png]
        case .tweak, .extra: return [.item, .folder]
        default: return [.item]
        }
    }

    var allowedExtensions: Set<String> {
        switch self {
        case .ipa: return ["ipa", "tipa"]
        case .tweak: return ["dylib", "deb", "framework"]
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

    @Published var isRunning = false
    @Published var logLines: [String] = []
    @Published var output: URL?
    @Published var errorMessage: String?

    private let inputsDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Inputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var canStart: Bool {
        guard ipa != nil, !tweaks.isEmpty, !isRunning else { return false }
        if signing.mode == .certificate {
            return signing.p12 != nil && signing.provision != nil
        }
        return true
    }

    func handleImport(_ result: Result<[URL], Error>, target: ImportTarget) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            for url in urls {
                guard target.allowedExtensions.contains(url.pathExtension.lowercased()) else {
                    errorMessage = "الملف \(url.lastPathComponent) غير مناسب. المسموح: \(target.allowedExtensions.sorted().joined(separator: ", "))"
                    continue
                }
                do {
                    let local = try copyIn(url)
                    switch target {
                    case .ipa: ipa = local
                    case .tweak: tweaks.append(local)
                    case .extra: extras.append(local)
                    case .icon: icon = local
                    case .p12: signing.p12 = local
                    case .provision: signing.provision = local
                    }
                } catch {
                    errorMessage = "تعذّر نسخ \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }

    /// Files from the picker are security-scoped; copy them into the sandbox right away.
    private func copyIn(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dir = inputsDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    func start() {
        guard let ipa, canStart else { return }
        let job = InjectionJob(ipa: ipa, tweaks: tweaks, extras: extras, icon: icon,
                               options: options, signing: signing)
        isRunning = true
        output = nil
        logLines = []

        Thread.detachNewThread { [weak self] in
            let injector = Injector { line in
                Task { @MainActor in self?.logLines.append(line) }
            }
            do {
                let url = try injector.run(job)
                Task { @MainActor in self?.finish(output: url, error: nil) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in self?.finish(output: nil, error: message) }
            }
        }
    }

    private func finish(output: URL?, error: String?) {
        if let error {
            logLines.append("❌ \(error)")
            errorMessage = error
        }
        self.output = output
        isRunning = false
    }

    func reset() {
        ipa = nil
        tweaks = []
        extras = []
        icon = nil
        output = nil
        logLines = []
        try? FileManager.default.removeItem(at: inputsDir)
        try? FileManager.default.createDirectory(at: inputsDir, withIntermediateDirectories: true)
    }
}
