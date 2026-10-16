import Foundation

/// How something shared to Cauldron is imported, chosen from what the share sheet gave.
public enum SharedImportRoute: Equatable, Sendable {
  /// A web link, read as if it had been typed into the import sheet.
  case link(String)
  /// An Instagram or TikTok post with its caption, which the share sheet provides. The caption
  /// goes down the pasted-text path, so no token is needed, and the post stays as the source.
  case caption(String, post: String)
  /// Text with no link: the pasted-text path.
  case text(String)
}
