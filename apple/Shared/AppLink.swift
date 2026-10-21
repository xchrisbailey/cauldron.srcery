import Foundation

/// A `cauldron://` link into the app. The widget builds them and the app reads them. Shared by
/// the app and the widget extension.
enum AppLink: Equatable, Sendable {
  /// The Tracker, on today's diary.
  case todayDiary
  case sharedDraft(UUID)

  static let scheme = "cauldron"

  var url: URL {
    switch self {
    case .sharedDraft(let id):
      URL(string: "\(Self.scheme)://shared-draft/\(id.uuidString)") ?? URL(filePath: "/")
    case .todayDiary: URL(string: "\(Self.scheme)://tracker/today") ?? URL(filePath: "/")
    }
  }

  /// The link `url` stands for, or nil for any other address.
  init?(url: URL) {
    guard url.scheme?.lowercased() == Self.scheme else { return nil }
    if url.host()?.lowercased() == "shared-draft" {
      guard url.query == nil, url.fragment == nil, url.user == nil, url.password == nil,
        url.pathComponents.count == 2, let id = UUID(uuidString: url.lastPathComponent)
      else { return nil }
      self = .sharedDraft(id)
      return
    }
    switch (url.host()?.lowercased(), url.path()) {
    case ("tracker", "/today"), ("tracker", "/today/"): self = .todayDiary
    default: return nil
    }
  }
}
