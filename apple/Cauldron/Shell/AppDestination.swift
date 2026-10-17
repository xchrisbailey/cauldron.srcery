import CauldronKit

/// Where the app can be: the four sections, and Settings. The shell keeps one of these as its
/// selection on every platform, so switching between tabs and a sidebar keeps your place.
enum AppDestination: Hashable, CaseIterable, Identifiable, Sendable {
  case recipes
  case week
  case gather
  case tracker
  case settings

  var id: Self { self }

  /// The four sections, in the order the tab bar and sidebar list them.
  static let sections: [AppDestination] = [.recipes, .week, .gather, .tracker]

  var title: CopyString {
    switch self {
    case .recipes: Copy.nav.recipes
    case .week: Copy.nav.week
    case .gather: Copy.nav.gather
    case .tracker: Copy.nav.tracker
    case .settings: Copy.settings.title
    }
  }

  /// An SF Symbol.
  var systemImage: String {
    switch self {
    case .recipes: "book.closed"
    case .week: "calendar"
    case .gather: "basket"
    case .tracker: "chart.line.uptrend.xyaxis"
    case .settings: "gearshape"
    }
  }
}

extension AppLink {
  /// The section a link opens. A link to today's diary opens the Tracker.
  var destination: AppDestination {
    switch self {
    case .todayDiary: .tracker
    }
  }
}
