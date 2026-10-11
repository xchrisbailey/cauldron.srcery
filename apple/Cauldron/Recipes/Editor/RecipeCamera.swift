import Foundation

#if canImport(UIKit)
  import UIKit
#endif

/// Taking a photo with the camera, on an iPhone or iPad. It is offered only when the app's
/// Info.plist has `NSCameraUsageDescription` (without it the system ends the app the moment the
/// camera opens) and the device has a camera, so adding that key to `project.yml` turns it on
/// with no code change here. The Mac uses the photo picker only.
enum RecipeCamera {
  static func isOffered(hasUsageDescription: Bool, cameraAvailable: Bool) -> Bool {
    hasUsageDescription && cameraAvailable
  }

  static var isOffered: Bool {
    #if os(iOS)
      isOffered(
        hasUsageDescription: Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription")
          != nil,
        cameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera))
    #else
      false
    #endif
  }
}
