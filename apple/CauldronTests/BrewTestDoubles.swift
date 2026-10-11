import Foundation

@testable import Cauldron

/// Notifications as a log of what was asked for.
@MainActor
final class RecordingAlerts: BrewAlerts {
  enum Call: Equatable {
    case permission
    case requestPermission
    case schedule(BrewAlert)
    case cancel(String)
  }

  var calls: [Call] = []
  /// What the system says before the cook is asked.
  var current = AlertPermission.notDetermined
  /// What the cook answers when asked.
  var answer = AlertPermission.granted

  func permission() async -> AlertPermission {
    calls.append(.permission)
    return current
  }

  func requestPermission() async -> AlertPermission {
    calls.append(.requestPermission)
    current = answer
    return answer
  }

  func schedule(_ alert: BrewAlert) async { calls.append(.schedule(alert)) }
  func cancel(id: String) async { calls.append(.cancel(id)) }

  var scheduled: [BrewAlert] {
    calls.compactMap { if case .schedule(let alert) = $0 { alert } else { nil } }
  }
  var cancelled: [String] {
    calls.compactMap { if case .cancel(let id) = $0 { id } else { nil } }
  }
  var requests: Int { calls.filter { $0 == .requestPermission }.count }
}

@MainActor
final class RecordingActivities: BrewActivities {
  enum Call: Equatable {
    case show(BrewActivityState)
    case end(String)
  }

  var calls: [Call] = []

  func show(_ state: BrewActivityState) async { calls.append(.show(state)) }
  func end(id: String) async { calls.append(.end(id)) }

  var shown: [BrewActivityState] {
    calls.compactMap { if case .show(let state) = $0 { state } else { nil } }
  }
  var ended: [String] {
    calls.compactMap { if case .end(let id) = $0 { id } else { nil } }
  }
}

@MainActor
final class InMemoryTimerStore: BrewTimerStore {
  var boards: [UUID: BrewTimerBoard] = [:]

  func load(recipeID: UUID) -> BrewTimerBoard? { boards[recipeID] }
  func save(_ board: BrewTimerBoard) { boards[board.recipeID] = board }
  func remove(recipeID: UUID) { boards[recipeID] = nil }
}

@MainActor
final class RecordingScreen: ScreenAwake {
  var states: [Bool] = []
  func keepAwake(_ on: Bool) { states.append(on) }
}

/// A clock the test moves.
@MainActor
final class TestClock {
  var date: Date
  init(_ date: Date = Date(timeIntervalSince1970: 1_000_000)) { self.date = date }
  func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
  var now: () -> Date { { [self] in date } }
}
