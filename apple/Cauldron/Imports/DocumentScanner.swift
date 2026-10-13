import CauldronKit
import Foundation

#if os(iOS)
  import AVFoundation
  import SwiftUI
  import UIKit
  import VisionKit
#endif

/// Whether the document scanner can open, and if not, why. The scanner is VisionKit's, on an
/// iPhone or iPad only; a Mac, a simulator and a device whose camera is refused each say so in
/// plain words and leave the photo library and pasting open.
enum ScannerAvailability: Equatable {
  case ready
  /// No scanner here: no camera, or the app can't ask for one.
  case unavailable
  /// The cook has said no to the camera in Settings.
  case refused

  enum Authorization: Equatable {
    case undecided
    case allowed
    case refused
  }

  /// `hasUsageDescription` is whether the app's Info.plist explains the camera: without it the
  /// system ends the app the moment a camera opens.
  static func resolve(
    hasUsageDescription: Bool, scannerSupported: Bool, authorization: Authorization
  ) -> ScannerAvailability {
    guard hasUsageDescription, scannerSupported else { return .unavailable }
    return authorization == .refused ? .refused : .ready
  }

  /// The words for why the scanner can't open; nil when it can.
  var message: CopyString? {
    switch self {
    case .ready: nil
    case .unavailable: Copy.importNative.scannerUnavailable
    case .refused: Copy.importNative.cameraRefused
    }
  }

  @MainActor static var current: ScannerAvailability {
    #if os(iOS)
      let authorization: Authorization =
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: .refused
        case .authorized: .allowed
        default: .undecided
        }
      return resolve(
        hasUsageDescription: Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription")
          != nil,
        scannerSupported: VNDocumentCameraViewController.isSupported, authorization: authorization)
    #else
      return .unavailable
    #endif
  }
}

#if os(iOS)
  /// The document scanner: several pages in one go, each straightened. It hands back one JPEG
  /// per page, in the order they were captured. Closing it without saving is a cancel.
  struct DocumentScanner: UIViewControllerRepresentable {
    let onPages: @MainActor ([Data]) -> Void
    let onCancel: @MainActor () -> Void
    let onFail: @MainActor () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
      let scanner = VNDocumentCameraViewController()
      scanner.delegate = context.coordinator
      return scanner
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
      Coordinator(onPages: onPages, onCancel: onCancel, onFail: onFail)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
      private let onPages: @MainActor ([Data]) -> Void
      private let onCancel: @MainActor () -> Void
      private let onFail: @MainActor () -> Void

      init(
        onPages: @escaping @MainActor ([Data]) -> Void,
        onCancel: @escaping @MainActor () -> Void, onFail: @escaping @MainActor () -> Void
      ) {
        self.onPages = onPages
        self.onCancel = onCancel
        self.onFail = onFail
      }

      // VisionKit calls its delegate on the main thread; the conformance is checked at runtime.
      func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
      ) {
        // The pages are held in memory and never written anywhere: each is encoded as it is
        // handed over. A page that can't be encoded is skipped.
        let pages = (0..<scan.pageCount).compactMap {
          scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9)
        }
        onPages(pages)
      }

      func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        onCancel()
      }

      func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFailWithError error: any Error
      ) {
        onFail()
      }
    }
  }
#endif
