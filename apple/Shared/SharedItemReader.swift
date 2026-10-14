import Foundation
import UniformTypeIdentifiers

/// Chooses what the share extension keeps from what the share sheet gave it. Shared with the
/// app so the choosing is tested there.
enum SharedItemReader {
  /// The first web link and the first text among what was shared, or nil when there is neither.
  /// A link that isn't http or https (a file, a mail address) is not a web link.
  @MainActor
  static func read(_ items: [NSExtensionItem]) async -> SharedItem? {
    var url: String?
    var text: String?
    for provider in items.flatMap({ $0.attachments ?? [] }) {
      if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
        let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
        let link = Self.url(from: loaded),
        ["http", "https"].contains(link.scheme?.lowercased() ?? "")
      {
        url = link.absoluteString
      } else if text == nil,
        provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
        let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
        let string = Self.string(from: loaded),
        !isBlank(string)
      {
        text = string
      }
    }
    // Some apps share their caption as the item's own text rather than an attachment.
    if text == nil {
      text = items.compactMap { $0.attributedContentText?.string }.first { !isBlank($0) }
    }
    guard url != nil || text != nil else { return nil }
    return SharedItem(url: url, text: text)
  }

  /// A provider hands over a `URL`, or the link's text as a string or as UTF-8 bytes,
  /// depending on the app and the platform.
  static func url(from item: any NSSecureCoding) -> URL? {
    if let url = item as? URL { return url }
    return string(from: item).flatMap {
      URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  /// Text as a string, an attributed string, or UTF-8 bytes.
  static func string(from item: any NSSecureCoding) -> String? {
    if let string = item as? String { return string }
    if let attributed = item as? NSAttributedString { return attributed.string }
    if let data = item as? Data { return String(data: data, encoding: .utf8) }
    return nil
  }

  private static func isBlank(_ string: String) -> Bool {
    string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
