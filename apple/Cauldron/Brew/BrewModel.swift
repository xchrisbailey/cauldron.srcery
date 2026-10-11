import CauldronKit
import Foundation
import Observation

/// Brewing one recipe: which step the cook is on, the timers, and the screen. The views read it
/// and call it; everything that decides anything is here, where it can be tested.
@MainActor
@Observable
final class BrewModel {
  /// What the timer button on a step will do.
  enum TimerAction: Equatable {
    case start
    case pause
    case resume
    case reset
  }

  let plan: BrewPlan
  let timers: BrewTimers
  private(set) var index = 0

  @ObservationIgnored private let screen: any ScreenAwake
  @ObservationIgnored private let now: () -> Date
  /// When the step last changed, so a second tap meant for "Next step" doesn't land on
  /// "Brewed" as it takes the button's place.
  @ObservationIgnored private var movedAt: Date?
  /// How soon after moving a tap on "Brewed" is taken for a double tap on "Next step".
  @ObservationIgnored private let settle: TimeInterval = 0.7

  init(
    plan: BrewPlan, timers: BrewTimers, screen: any ScreenAwake,
    now: @escaping () -> Date = { .now }
  ) {
    self.plan = plan
    self.timers = timers
    self.screen = screen
    self.now = now
  }

  // MARK: Lifecycle

  /// The brew screen came up: keep the screen on and pick up timers left running.
  func begin() async {
    screen.keepAwake(true)
    await timers.restore()
  }

  /// The brew screen went away. Timers keep running; the screen may sleep again.
  func end() {
    screen.keepAwake(false)
  }

  // MARK: Steps

  var hasSteps: Bool { plan.count > 0 }
  var step: Step? { plan.step(at: index) }
  var canGoBack: Bool { index > 0 }
  var canGoForward: Bool { index < plan.count - 1 }
  var isLast: Bool { hasSteps && index == plan.count - 1 }
  var progress: Double { hasSteps ? Double(index + 1) / Double(plan.count) : 0 }

  func go(to target: Int) {
    let next = min(max(0, target), max(0, plan.count - 1))
    guard next != index else { return }
    index = next
    movedAt = now()
  }

  func next() { go(to: index + 1) }
  func previous() { go(to: index - 1) }

  // MARK: Timers

  var timerSeconds: Int? { plan.timerSeconds(for: index) }

  var timerAction: TimerAction? {
    guard timerSeconds != nil else { return nil }
    switch timers.timer(for: index)?.state {
    case nil: return .start
    case .running: return .pause
    case .paused: return .resume
    case .done: return .reset
    }
  }

  /// The timers of the other steps, which keep running while the cook is elsewhere.
  var otherTimers: [BrewTimer] { timers.board.timers.filter { $0.step != index } }

  func toggleTimer() async {
    guard let seconds = timerSeconds, let action = timerAction else { return }
    switch action {
    case .start: await timers.start(step: index, seconds: seconds)
    case .pause: await timers.pause(step: index)
    case .resume: await timers.resume(step: index)
    case .reset: await timers.reset(step: index)
    }
  }

  func resetTimer() async { await timers.reset(step: index) }
  func addMinute() async { await timers.addMinute(step: index) }

  // MARK: Finishing

  /// "Brewed": records that the recipe was cooked (`markCooked`) and ends the timers. Returns
  /// false, doing nothing, for a tap that came right after moving to the last step. If
  /// `markCooked` throws, the timers are left running and the error is passed on.
  func finish(markCooked: () throws -> Void) async throws -> Bool {
    if let movedAt, now().timeIntervalSince(movedAt) < settle { return false }
    try markCooked()
    await timers.resetAll()
    return true
  }
}
