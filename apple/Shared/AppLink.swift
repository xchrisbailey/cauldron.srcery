import Foundation

/// A `cauldron://` link into the app. The widget builds them and the app reads them. Shared by
/// the app and the widget extension.
enum AppLink: Equatable, Sendable {
  /// The Tracker, on today's diary.
  case todayDiary

  static let scheme = "cauldron"

  var url: URL {
    switch self {
    case .todayDiary: URL(string: "\(Self.scheme)://tracker/today") ?? URL(filePath: "/")
    }
  }

  /// The link `url` stands for, or nil for any other address.
  init?(url: URL) {
    guard url.scheme?.lowercased() == Self.scheme else { return nil }
    switch (url.host()?.lowercased(), url.path()) {
    case ("tracker", "/today"), ("tracker", "/today/"): self = .todayDiary
    default: return nil
    }
  }
}
