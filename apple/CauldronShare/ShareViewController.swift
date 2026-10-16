import CauldronImports
import CauldronKit
import SwiftUI

#if os(iOS)
  import UIKit
  typealias PlatformViewController = UIViewController
  typealias PlatformHostingController = UIHostingController
#else
  import AppKit
  typealias PlatformViewController = NSViewController
  typealias PlatformHostingController = NSHostingController
#endif

/// The share sheet's Cauldron entry. It reads the first link and any text it was given, runs the
/// import and shows the recipe it found. Save leaves the finished recipe in the App Group's
/// inbox for the app to put in the recipe box; Edit in Cauldron, and every failure, leave the
/// link or text for the app to open as a draft, as before. A share extension can't open its app
/// or the app's store, so the app takes either the next time it comes forward.
///
/// The sheet closes only after what it is leaving is written. How the item is chosen is
/// `SharedItemReader`; what the sheet does is `ShareSheetModel`, and how it looks is
/// `ShareSheetView`.
final class ShareViewController: PlatformViewController {
  #if os(macOS)
    override func loadView() {
      view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 320))
    }
  #endif

  override func viewDidLoad() {
    super.viewDidLoad()
    Task { @MainActor in
      let item = await SharedItemReader.read(
        extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      guard let item else {
        show(ShareConfirmation(outcome: .failed(Copy.importNative.nothingToSend.text)))
        try? await Task.sleep(for: .seconds(1.6))
        extensionContext?.completeRequest(returningItems: nil)
        return
      }
      show(
        ShareSheetView(
          model: ShareSheetModel.live(item: item) { [weak self] closing in
            self?.close(closing)
          }))
    }
  }

  private func close(_ closing: ShareSheetModel.Closing) {
    switch closing {
    case .done:
      extensionContext?.completeRequest(returningItems: nil)
    case .cancelled:
      extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
  }

  private func show(_ content: some View) {
    let host = PlatformHostingController(rootView: content)
    addChild(host)
    host.view.frame = view.bounds
    #if os(iOS)
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    #else
      host.view.autoresizingMask = [.width, .height]
    #endif
    view.addSubview(host.view)
  }
}
