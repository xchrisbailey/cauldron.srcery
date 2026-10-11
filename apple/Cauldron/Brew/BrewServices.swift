import Foundation

// What brewing needs from the system, as protocols with a live implementation and a test
// double each (see `BrewTimers`): notifications, Live Activities, device-local storage and the
// screen's idle timer. Everything runs on the main actor.

/// Whether the system lets Cauldron post notifications.
enum AlertPermission: Equatable, Sendable {
  case notDetermined
  case granted
  case denied
}

/// A notification to deliver at a time, even with the app suspended. Scheduling one with an id
/// already scheduled replaces it.
struct BrewAlert: Equatable, Sendable {
  var id: String
  var title: String
  var body: String
  var fireAt: Date
}

@MainActor
protocol BrewAlerts: AnyObject {
  /// The current permission, without asking.
  func permission() async -> AlertPermission
  /// Asks the cook, once; answers with what they chose.
  func requestPermission() async -> AlertPermission
  func schedule(_ alert: BrewAlert) async
  func cancel(id: String) async
}

/// What a step's Live Activity shows.
struct BrewActivityState: Equatable, Sendable {
  enum Phase: Equatable, Sendable {
    case running(endsAt: Date)
    case paused(remaining: Int)
    case finished
  }

  var id: String
  var recipeTitle: String
  /// Counted from 1.
  var stepNumber: Int
  var label: String
  var totalSeconds: Int
  var phase: Phase
}

@MainActor
protocol BrewActivities: AnyObject {
  /// Starts the step's activity, or updates it when it is already showing.
  func show(_ state: BrewActivityState) async
  func end(id: String) async
}

/// Where running timers are kept so they survive a relaunch. Device-local: a timer is only
/// meaningful on the phone or Mac it was started on, so it is never in the synced store.
@MainActor
protocol BrewTimerStore: AnyObject {
  func load(recipeID: UUID) -> BrewTimerBoard?
  func save(_ board: BrewTimerBoard)
  func remove(recipeID: UUID)
}

/// Keeps the screen on while a recipe is brewed.
@MainActor
protocol ScreenAwake: AnyObject {
  func keepAwake(_ on: Bool)
}
