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

/// The share sheet's Cauldron entry. It does as little as it can: it reads the first link and
/// any text it was given, leaves them in the App Group's inbox, says so, and closes. A share
/// extension can't open its app, so the app runs the import and opens the draft the next time
/// the cook opens it, and the confirmation says that. How the item is chosen is
/// `SharedItemReader`; how the confirmation looks is `ShareConfirmation`.
final class ShareViewController: PlatformViewController {
  #if os(macOS)
    override func loadView() {
      view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
    }
  #endif

  override func viewDidLoad() {
    super.viewDidLoad()
    Task { @MainActor in
      let item = await SharedItemReader.read(
        extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      show(Self.outcome(of: item), keyNote: Self.keyNote())
      try? await Task.sleep(for: .seconds(1.6))
      extensionContext?.completeRequest(returningItems: nil)
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

  /// For now (#200): whether the AI key the app saved can be read here, for the provider the
  /// app has chosen. It says only whether there is one; the key itself is never shown.
  private static func keyNote() -> String {
    let defaults = RecipeAIService.sharedDefaults ?? .standard
    let provider = RecipeAIService.chosenProvider(defaults)
    let found = KeychainKeyStore(provider: provider).key() != nil
    return (found ? Copy.importNative.aiKeyAvailable : Copy.importNative.noAIKey).text
  }

  private func show(_ outcome: ShareConfirmation.Outcome, keyNote: String?) {
    let host = PlatformHostingController(
      rootView: ShareConfirmation(outcome: outcome, keyNote: keyNote))
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
