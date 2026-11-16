import Foundation

enum SigningMode: String, CaseIterable, Identifiable {
    case none
    case adhoc
    case certificate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "بدون توقيع"
        case .adhoc: return "Fakesign"
        case .certificate: return "بشهادة"
        }
    }

    var footnote: String {
        switch self {
        case .none:
            return "يُخرج IPA غير موقّع. وقّعه لاحقاً بأي أداة (Sideloadly، ESign، TrollStore…)."
        case .adhoc:
            return "توقيع وهمي (ad-hoc) بدون شهادة، يعمل مع TrollStore أو AppSync."
        case .certificate:
            return "يحتاج ملف ‎.p12‎ وكلمة مروره وملف ‎.mobileprovision‎ مطابق."
        }
    }
}

enum InjectLocation: String, CaseIterable, Identifiable {
    case rpath
    case executablePath

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rpath: return "@rpath"
        case .executablePath: return "@executable_path"
        }
    }

    /// Load path written into the main executable for a dylib copied to `App.app/Frameworks/`.
    func loadPath(for fileName: String) -> String {
        switch self {
        case .rpath: return "@rpath/\(fileName)"
        case .executablePath: return "@executable_path/Frameworks/\(fileName)"
        }
    }
}

struct InjectOptions {
    var location: InjectLocation = .rpath
    var weakInject = false
    var fixSubstratePaths = true
    var skipEncryptionCheck = false

    var bundleID = ""
    var displayName = ""
    var version = ""

    var removeURLSchemes = false
    var enableDocumentBrowser = false
    var removeExtensions = false
    var removeWatchApp = false
    var removeSupportedDevices = false
}

struct SigningConfig {
    var mode: SigningMode = .none
    var p12: URL?
    var password = ""
    var provision: URL?
}

struct InjectionJob {
    var ipa: URL
    var tweaks: [URL]
    var extras: [URL]
    var icon: URL?
    var options: InjectOptions
    var signing: SigningConfig
}

struct InjectorError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
