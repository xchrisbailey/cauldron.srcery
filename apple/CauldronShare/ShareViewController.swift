import CauldronKit
import SwiftUI
import UniformTypeIdentifiers

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
/// any text it was given, leaves them in the App Group's inbox, says so, and closes. The app
/// runs the import and opens the draft the next time it comes forward.
final class ShareViewController: PlatformViewController {
  private var message = Copy.importNative.sentToCauldron.text

  #if os(macOS)
    override func loadView() {
      view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
    }
  #endif

  override func viewDidLoad() {
    super.viewDidLoad()
    Task { @MainActor in
      let item = await Self.read(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      if let item, (try? ShareInbox.add(item)) != nil {
        message = Copy.importNative.sentToCauldron.text
      } else {
        message = Copy.importNative.nothingToSend.text
      }
      show(message)
      try? await Task.sleep(for: .seconds(1.6))
      extensionContext?.completeRequest(returningItems: nil)
    }
  }

  private func show(_ text: String) {
    let host = PlatformHostingController(rootView: ShareConfirmation(text: text))
    addChild(host)
    host.view.frame = view.bounds
    #if os(iOS)
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    #else
      host.view.autoresizingMask = [.width, .height]
    #endif
    view.addSubview(host.view)
  }

  /// The first web link and the first text among what was shared.
  private static func read(_ items: [NSExtensionItem]) async -> SharedItem? {
    var url: String?
    var text: String?
    for provider in items.flatMap({ $0.attachments ?? [] }) {
      if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
        let link = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
        ["http", "https"].contains(link.scheme?.lowercased() ?? "")
      {
        url = link.absoluteString
      } else if text == nil,
        provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
        let string = try? await provider.loadItem(
          forTypeIdentifier: UTType.plainText.identifier) as? String,
        !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        text = string
      }
    }
    // Some apps share their caption as the item's own text rather than an attachment.
    if text == nil {
      text = items.compactMap { $0.attributedContentText?.string }.first {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
    }
    guard url != nil || text != nil else { return nil }
    return SharedItem(url: url, text: text)
  }
}

private struct ShareConfirmation: View {
  let text: String

  var body: some View {
    Label {
      Text(verbatim: text)
    } icon: {
      Image(systemName: "flame")
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
