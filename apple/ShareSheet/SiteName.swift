import Foundation

/// The name of the site a link is on, for the places that show where a recipe came from. Shared
/// by the share sheet and the app, so both say it the same way.
enum SiteName {
  /// The link's host, less a leading "www."; nil when it isn't a link with a host.
  static func of(_ link: String) -> String? {
    guard let host = URL(string: link)?.host(), !host.isEmpty else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}
