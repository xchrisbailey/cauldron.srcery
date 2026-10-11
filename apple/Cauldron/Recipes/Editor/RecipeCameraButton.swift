import CauldronKit
import SwiftUI

/// "Take a photo" in the editor: shows only where the camera can be used (`RecipeCamera`),
/// and hands back the photo's bytes for the same processing as a picked one.
struct RecipeCameraButton: View {
  let onPhoto: (Data) -> Void

  #if os(iOS)
    @State private var capturing = false

    var body: some View {
      if RecipeCamera.isOffered {
        Button {
          capturing = true
        } label: {
          Label {
            Text(verbatim: Copy.recipeEditor.takePhoto.text)
          } icon: {
            Image(systemName: "camera")
          }
        }
        .fullScreenCover(isPresented: $capturing) {
          CameraCapture(
            onPhoto: { data in
              capturing = false
              onPhoto(data)
            }, onCancel: { capturing = false }
          )
          .ignoresSafeArea()
        }
      }
    }
  #else
    var body: some View { EmptyView() }
  #endif
}

#if os(iOS)
  import UIKit

  /// The system camera.
  private struct CameraCapture: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.delegate = context.coordinator
      return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
      UINavigationControllerDelegate
    {
      let parent: CameraCapture

      init(_ parent: CameraCapture) {
        self.parent = parent
      }

      func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
      ) {
        if let image = info[.originalImage] as? UIImage,
          let data = image.jpegData(compressionQuality: 0.95)
        {
          parent.onPhoto(data)
        } else {
          parent.onCancel()
        }
      }

      func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        parent.onCancel()
      }
    }
  }
#endif
