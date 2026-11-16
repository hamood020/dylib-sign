import UIKit
import UniformTypeIdentifiers

/// Presents UIDocumentPickerViewController directly from UIKit.
/// SwiftUI's .fileImporter gets stuck when its configuration changes between presentations
/// (the "Open" button does nothing / some files can't be picked), so we avoid it.
final class DocumentPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPicker()

    private var completion: (([URL]) -> Void)?

    func present(types: [UTType], allowsMultiple: Bool, completion: @escaping ([URL]) -> Void) {
        guard let top = Self.topViewController() else { return }
        // asCopy: the system copies the picked items into our sandbox (no security scope needed).
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        self.completion = completion
        top.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let done = completion
        completion = nil
        done?(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion = nil
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
