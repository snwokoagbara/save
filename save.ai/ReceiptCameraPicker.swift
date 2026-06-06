import SwiftUI
import UIKit

struct ReceiptCameraPicker: UIViewControllerRepresentable {
    let didCapture: (UIImage) -> Void
    let didCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(didCapture: didCapture, didCancel: didCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let didCapture: (UIImage) -> Void
        private let didCancel: () -> Void

        init(
            didCapture: @escaping (UIImage) -> Void,
            didCancel: @escaping () -> Void
        ) {
            self.didCapture = didCapture
            self.didCancel = didCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                didCapture(image)
            } else {
                didCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            didCancel()
        }
    }
}
