#if canImport(ActivityKit) && os(iOS)
  import ActivityKit
  import Foundation

  /// A step timer shown on the Lock Screen and in the Dynamic Island while a recipe is brewed.
  /// The app starts and updates the activity; the widget extension draws it. This file is
  /// compiled into both.
  struct BrewTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
      /// When the timer runs out. Nil while it is paused.
      var endsAt: Date?
      /// What is left while paused, in seconds.
      var remainingSeconds: Int
      var finished: Bool
    }

    var recipeTitle: String
    /// The step the timer belongs to, counted from 1.
    var stepNumber: Int
    /// The timer's label, as the step wrote it ("simmer 20 minutes").
    var label: String
    var totalSeconds: Int
  }
#endif
