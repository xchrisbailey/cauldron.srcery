import CauldronImports
import CauldronKit
import Foundation

extension SharedImportRoute {
  /// The route for `item`, or nil when it holds nothing to read (the extension doesn't leave
  /// such an item, but a damaged one is skipped rather than opening an empty sheet). Shared by
  /// the share sheet, which reads the item at once, and the app, which opens it as a draft.
  init?(_ item: SharedItem) {
    let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let link = item.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !link.isEmpty {
      // A caption beats the link only for a post. Some platforms put the link in the caption
      // too, so it is taken out before judging whether any caption is left.
      if Distill.classify(link) != .web {
        let caption = text.replacingOccurrences(of: link, with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
          self = .caption(caption, post: link)
          return
        }
      }
      self = .link(link)
      return
    }
    guard !text.isEmpty else { return nil }
    // Some apps share a link as plain text. Pasted into the paste box it would be no recipe.
    if !text.contains(where: \.isWhitespace), Distill.isAcceptedLink(text) {
      self = .link(text)
    } else {
      self = .text(text)
    }
  }
}
