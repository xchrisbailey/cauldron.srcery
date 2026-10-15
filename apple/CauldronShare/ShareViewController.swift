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

/// The share sheet's Cauldron entry. It does as little as it can: it reads the first link and
/// any text it was given, leaves them in the App Group's inbox, says so, and closes. A share
/// extension can't open its app, so the app runs the import and opens the draft the next time
/// the cook opens it, and the confirmation says that. How the item is chosen is
/// `SharedItemReader`; how the confirmation looks is `ShareConfirmation`.
final class ShareViewController: PlatformViewController {
  #if os(macOS)
    override func loadView() {
      #if DEBUG
        // PROTOTYPE (#195): room for the review sheet.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 640))
      #else
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
      #endif
    }
  #endif

  override func viewDidLoad() {
    super.viewDidLoad()
    Task { @MainActor in
      let item = await SharedItemReader.read(
        extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      // PROTOTYPE (#195): debug builds show the review sheet prototype instead. Throwaway.
      #if DEBUG
        embed(
          SharePreviewPrototype(sharedLink: item?.url) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
          })
      #else
        show(Self.outcome(of: item))
        try? await Task.sleep(for: .seconds(1.6))
        extensionContext?.completeRequest(returningItems: nil)
      #endif
    }
  }

  /// Leaves `item` for the app, and what to tell the cook about it.
  private static func outcome(of item: SharedItem?) -> ShareConfirmation.Outcome {
    guard let item else { return .failed(Copy.importNative.nothingToSend.text) }
    guard (try? ShareInbox.add(item)) != nil else {
      return .failed(Copy.importNative.couldntSend.text)
    }
    return .sent(
      title: Copy.importNative.sentToCauldron.text, detail: Copy.importNative.opensAsDraft.text)
  }

  private func show(_ outcome: ShareConfirmation.Outcome) {
    embed(ShareConfirmation(outcome: outcome))
  }

  private func embed(_ root: some View) {
    let host = PlatformHostingController(rootView: root)
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
