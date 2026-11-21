// The pickers of the attach button on iOS: photo library (PHPicker), camera (UIImagePickerController)
// and documents (UIDocumentPicker). License: MIT.
#if os(iOS) && canImport(SwiftUI)
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the customer chose in the attach menu.
enum OryksaAttachSource: String, Identifiable {
    case gallery, camera, document
    var id: String { rawValue }
}

/// True when the camera can be offered: the device has one and the app's Info.plist has
/// `NSCameraUsageDescription` (without it iOS closes the app when the camera opens).
var oryksaCameraAvailable: Bool {
    UIImagePickerController.isSourceTypeAvailable(.camera)
        && Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
}

/// A camera photo as a JPEG of at most 1600 pixels on its longest side, at 80%.
func oryksaJpeg(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
    let w = image.size.width * image.scale, h = image.size.height * image.scale
    guard w > 0, h > 0 else { return nil }
    let k = min(1, maxSide / max(w, h))
    let size = CGSize(width: (w * k).rounded(), height: (h * k).rounded())
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return out.jpegData(compressionQuality: quality)
}

/// What came back from a picker.
enum OryksaPicked {
    case cancelled
    /// The file could not be read.
    case failed
    case picked(OryksaAttachment)
}

/// Shows the picker for `source` and gives back what to send.
struct OryksaAttachPicker: UIViewControllerRepresentable {
    let source: OryksaAttachSource
    let done: (OryksaPicked) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done) }

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .gallery:
            var cfg = PHPickerConfiguration()
            cfg.filter = .images
            cfg.selectionLimit = 1
            let p = PHPickerViewController(configuration: cfg)
            p.delegate = context.coordinator
            return p
        case .camera:
            let p = UIImagePickerController()
            p.sourceType = .camera
            p.delegate = context.coordinator
            return p
        case .document:
            var types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .image]
            for ext in ["doc", "docx", "csv", "txt"] { if let t = UTType(filenameExtension: ext) { types.append(t) } }
            let p = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            p.allowsMultipleSelection = false
            p.delegate = context.coordinator
            return p
        }
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate, UIDocumentPickerDelegate {
        let done: (OryksaPicked) -> Void
        init(_ done: @escaping (OryksaPicked) -> Void) { self.done = done }

        private func finish(_ p: OryksaPicked) { DispatchQueue.main.async { self.done(p) } }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let item = results.first?.itemProvider, item.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                return finish(.cancelled)
            }
            item.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data = data, let jpeg = oryksaJpeg(data) else { return self.finish(.failed) }
                self.finish(.picked(oryksaPhotoAttachment(jpeg)))
            }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let img = info[.originalImage] as? UIImage, let jpeg = oryksaJpeg(img) else { return finish(.failed) }
            finish(.picked(oryksaPhotoAttachment(jpeg)))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(.cancelled) }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return finish(.cancelled) }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > oryksaMaxFileBytes { return finish(.picked(.tooBig)) }
            guard let data = try? Data(contentsOf: url) else { return finish(.failed) }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            finish(.picked(oryksaDocumentAttachment(data: data, name: url.lastPathComponent, mime: mime)))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(.cancelled) }
    }
}
#endif
