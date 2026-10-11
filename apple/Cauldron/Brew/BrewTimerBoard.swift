import Foundation

/// One step's timer. The truth is an end date (or what was left when it was paused), never a
/// counter, so it is right after the app was suspended, killed or relaunched.
struct BrewTimer: Codable, Equatable, Sendable {
  enum State: Codable, Equatable, Sendable {
    case running(endsAt: Date)
    case paused(remaining: Int)
    case done
  }

  /// The step it belongs to, counted from 0.
  var step: Int
  /// How long it was set for, with any minutes added.
  var totalSeconds: Int
  var state: State
}

/// The timers of one recipe being brewed: any number at once, one per step. A plain value with
/// the clock passed in, so every transition runs without a clock or a view.
struct BrewTimerBoard: Codable, Equatable, Sendable {
  var recipeID: UUID
  var recipeTitle: String
  private(set) var timers: [BrewTimer] = []

  init(recipeID: UUID, recipeTitle: String) {
    self.recipeID = recipeID
    self.recipeTitle = recipeTitle
  }

  func timer(for step: Int) -> BrewTimer? { timers.first { $0.step == step } }

  var hasRunning: Bool {
    timers.contains { if case .running = $0.state { true } else { false } }
  }

  /// Seconds left at `now`, rounded up so a timer never reads zero before it is done.
  func remaining(of step: Int, now: Date) -> Int {
    guard let timer = timer(for: step) else { return 0 }
    switch timer.state {
    case .running(let endsAt): return max(0, Int((endsAt.timeIntervalSince(now)).rounded(.up)))
    case .paused(let remaining): return remaining
    case .done: return 0
    }
  }

  /// Starts a timer of `seconds`. A paused one resumes where it was and a running one is left
  /// alone; a timer that has finished starts again.
  mutating func start(step: Int, seconds: Int, now: Date) {
    switch timer(for: step)?.state {
    case .paused: resume(step: step, now: now)
    case .running: break
    case .done, nil:
      set(
        BrewTimer(
          step: step, totalSeconds: seconds,
          state: .running(endsAt: now.addingTimeInterval(TimeInterval(seconds)))))
    }
  }

  mutating func pause(step: Int, now: Date) {
    guard var timer = timer(for: step), case .running = timer.state else { return }
    timer.state = .paused(remaining: remaining(of: step, now: now))
    set(timer)
  }

  mutating func resume(step: Int, now: Date) {
    guard var timer = timer(for: step), case .paused(let remaining) = timer.state else { return }
    timer.state = .running(endsAt: now.addingTimeInterval(TimeInterval(remaining)))
    set(timer)
  }

  /// One more minute, on a running or paused timer.
  mutating func addMinute(step: Int, now: Date) {
    guard var timer = timer(for: step) else { return }
    switch timer.state {
    case .running(let endsAt): timer.state = .running(endsAt: endsAt.addingTimeInterval(60))
    case .paused(let remaining): timer.state = .paused(remaining: remaining + 60)
    case .done: return
    }
    timer.totalSeconds += 60
    set(timer)
  }

  mutating func reset(step: Int) {
    timers.removeAll { $0.step == step }
  }

  mutating func resetAll() {
    timers = []
  }

  /// Marks every running timer whose end has passed as done, and returns their steps (once:
  /// a done timer isn't reported again), in step order.
  @discardableResult
  mutating func finishDue(now: Date) -> [Int] {
    var finished: [Int] = []
    for index in timers.indices {
      if case .running(let endsAt) = timers[index].state, endsAt <= now {
        timers[index].state = .done
        finished.append(timers[index].step)
      }
    }
    return finished.sorted()
  }

  private mutating func set(_ timer: BrewTimer) {
    if let index = timers.firstIndex(where: { $0.step == timer.step }) {
      timers[index] = timer
    } else {
      timers.append(timer)
      timers.sort { $0.step < $1.step }
    }
  }
}
