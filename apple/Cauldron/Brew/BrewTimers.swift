import CauldronKit
import Foundation
import Observation

/// The timers of the recipe being brewed, kept honest across everything an app can go through.
/// It changes a `BrewTimerBoard` and, for each step that changed, tells the system what the
/// timer now means: a notification is scheduled when a timer starts (so it fires with the app
/// suspended) and cancelled or moved when the timer is paused, resumed, extended or reset, and
/// a Live Activity follows the same changes. Every change is saved, so a relaunch finds the
/// timers where they were.
@MainActor
@Observable
final class BrewTimers {
  private(set) var board: BrewTimerBoard
  private(set) var permission = AlertPermission.notDetermined

  @ObservationIgnored private let store: any BrewTimerStore
  @ObservationIgnored private let alerts: any BrewAlerts
  @ObservationIgnored private let activities: any BrewActivities
  @ObservationIgnored private let now: () -> Date

  init(
    recipeID: UUID, recipeTitle: String, store: any BrewTimerStore, alerts: any BrewAlerts,
    activities: any BrewActivities, now: @escaping () -> Date = { .now }
  ) {
    board = BrewTimerBoard(recipeID: recipeID, recipeTitle: recipeTitle)
    self.store = store
    self.alerts = alerts
    self.activities = activities
    self.now = now
  }

  /// True once the cook has refused notifications, so the screen can say a timer won't alert
  /// them while they're away.
  var notificationsRefused: Bool { permission == .denied }

  // MARK: Reading

  func remaining(of step: Int) -> Int { board.remaining(of: step, now: now()) }
  func timer(for step: Int) -> BrewTimer? { board.timer(for: step) }

  // MARK: Changing

  /// Picks the timers up from where the last run left them: any that ran out meanwhile are
  /// done (their notification already fired), and the rest are scheduled and shown again.
  func restore() async {
    permission = await alerts.permission()
    guard let saved = store.load(recipeID: board.recipeID) else { return }
    board = saved
    board.finishDue(now: now())
    persist()
    for timer in board.timers { await sync(step: timer.step) }
  }

  func start(step: Int, seconds: Int) async {
    if board.timers.isEmpty { await askForPermission() }
    board.start(step: step, seconds: seconds, now: now())
    await changed(step)
  }

  func pause(step: Int) async {
    board.pause(step: step, now: now())
    await changed(step)
  }

  func resume(step: Int) async {
    board.resume(step: step, now: now())
    await changed(step)
  }

  func addMinute(step: Int) async {
    board.addMinute(step: step, now: now())
    await changed(step)
  }

  func reset(step: Int) async {
    board.reset(step: step)
    await changed(step)
  }

  /// Ends every timer, for when the recipe is done.
  func resetAll() async {
    let steps = board.timers.map(\.step)
    board.resetAll()
    persist()
    for step in steps { await sync(step: step) }
  }

  /// Notices timers that ran out. Called as the screen ticks; the notification for each was
  /// scheduled when it started, so this only brings the screen and the activity up to date.
  @discardableResult
  func refresh() async -> [Int] {
    let finished = board.finishDue(now: now())
    guard !finished.isEmpty else { return [] }
    persist()
    for step in finished { await sync(step: step) }
    return finished
  }

  // MARK: Telling the system

  private func askForPermission() async {
    if permission == .notDetermined { permission = await alerts.permission() }
    if permission == .notDetermined { permission = await alerts.requestPermission() }
  }

  private func changed(_ step: Int) async {
    persist()
    await sync(step: step)
  }

  private func persist() {
    if board.timers.isEmpty {
      store.remove(recipeID: board.recipeID)
    } else {
      store.save(board)
    }
  }

  private func id(_ step: Int) -> String { "brew.\(board.recipeID.uuidString).\(step)" }

  /// Makes the notification and the Live Activity say what the step's timer says now.
  private func sync(step: Int) async {
    let id = id(step)
    guard let timer = board.timer(for: step) else {
      await alerts.cancel(id: id)
      await activities.end(id: id)
      return
    }
    let phase: BrewActivityState.Phase
    switch timer.state {
    case .running(let endsAt):
      if permission == .granted {
        await alerts.schedule(
          BrewAlert(
            id: id, title: Copy.brewing.timeUp.text,
            body: Copy.brewing.timerDone(board.recipeTitle, step + 1).text, fireAt: endsAt))
      }
      phase = .running(endsAt: endsAt)
    case .paused(let remaining):
      await alerts.cancel(id: id)
      phase = .paused(remaining: remaining)
    case .done:
      // Its notification fired at the end, or is firing now: nothing to take back.
      phase = .finished
    }
    await activities.show(
      BrewActivityState(
        id: id, recipeTitle: board.recipeTitle, stepNumber: step + 1,
        label: Copy.brewing.timerFor(step + 1).text, totalSeconds: timer.totalSeconds,
        phase: phase))
  }
}
