import CauldronKit
import Foundation
import Testing

@Suite("Brew timer board")
struct BrewTimerBoardTests {
  private let t0 = Date(timeIntervalSince1970: 1_000_000)
  private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
  private func board() -> BrewTimerBoard { BrewTimerBoard(recipeID: UUID(), recipeTitle: "Soup") }

  @Test func aStartedTimerEndsItsLengthFromNow() {
    var board = board()
    board.start(step: 2, seconds: 600, now: t0)
    #expect(board.timer(for: 2)?.state == .running(endsAt: at(600)))
    #expect(board.remaining(of: 2, now: t0) == 600)
    #expect(board.remaining(of: 2, now: at(100.2)) == 500)
    #expect(board.timer(for: 1) == nil)
  }

  @Test func theTimeLeftRoundsUpSoItNeverReadsZeroBeforeItIsDone() {
    var board = board()
    board.start(step: 0, seconds: 10, now: t0)
    #expect(board.remaining(of: 0, now: at(9.5)) == 1)
    #expect(board.remaining(of: 0, now: at(10)) == 0)
    #expect(board.remaining(of: 0, now: at(50)) == 0)
  }

  @Test func pausingKeepsWhatWasLeftAndResumingRunsItFromThere() {
    var board = board()
    board.start(step: 0, seconds: 600, now: t0)
    board.pause(step: 0, now: at(100))
    #expect(board.timer(for: 0)?.state == .paused(remaining: 500))
    // Time passing while paused costs nothing.
    #expect(board.remaining(of: 0, now: at(5_000)) == 500)
    board.resume(step: 0, now: at(1_000))
    #expect(board.timer(for: 0)?.state == .running(endsAt: at(1_500)))
  }

  @Test func pausingOrResumingTheWrongStateChangesNothing() {
    var board = board()
    board.pause(step: 0, now: t0)
    board.resume(step: 0, now: t0)
    #expect(board.timers.isEmpty)
    board.start(step: 0, seconds: 60, now: t0)
    board.resume(step: 0, now: at(1))
    #expect(board.timer(for: 0)?.state == .running(endsAt: at(60)))
  }

  @Test func addingAMinuteMovesTheEndOrGrowsWhatIsLeft() {
    var board = board()
    board.start(step: 0, seconds: 120, now: t0)
    board.addMinute(step: 0, now: at(30))
    #expect(board.timer(for: 0)?.state == .running(endsAt: at(180)))
    #expect(board.timer(for: 0)?.totalSeconds == 180)
    board.pause(step: 0, now: at(60))
    board.addMinute(step: 0, now: at(70))
    #expect(board.timer(for: 0)?.state == .paused(remaining: 180))
    #expect(board.timer(for: 0)?.totalSeconds == 240)
  }

  @Test func aTimerIsDoneOnceItsEndHasPassedAndOnlyThenReportedOnce() {
    var board = board()
    board.start(step: 1, seconds: 60, now: t0)
    board.start(step: 3, seconds: 300, now: t0)
    #expect(board.finishDue(now: at(59)).isEmpty)
    #expect(board.finishDue(now: at(60)) == [1])
    #expect(board.timer(for: 1)?.state == .done)
    #expect(board.remaining(of: 1, now: at(61)) == 0)
    // Reported once; the other keeps running.
    #expect(board.finishDue(now: at(100)).isEmpty)
    #expect(board.timer(for: 3)?.state == .running(endsAt: at(300)))
    #expect(board.finishDue(now: at(10_000)) == [3])
  }

  @Test func severalTimersFinishTogetherWhenTheAppWasAsleep() {
    var board = board()
    board.start(step: 4, seconds: 60, now: t0)
    board.start(step: 1, seconds: 120, now: t0)
    #expect(board.finishDue(now: at(500)) == [1, 4])
  }

  @Test func aDoneTimerCantBePausedResumedOrExtendedButCanStartAgain() {
    var board = board()
    board.start(step: 0, seconds: 60, now: t0)
    board.finishDue(now: at(60))
    board.pause(step: 0, now: at(61))
    board.resume(step: 0, now: at(61))
    board.addMinute(step: 0, now: at(61))
    #expect(board.timer(for: 0)?.state == .done)
    board.start(step: 0, seconds: 60, now: at(100))
    #expect(board.timer(for: 0)?.state == .running(endsAt: at(160)))
  }

  @Test func startingAPausedTimerResumesIt() {
    var board = board()
    board.start(step: 0, seconds: 600, now: t0)
    board.pause(step: 0, now: at(100))
    board.start(step: 0, seconds: 600, now: at(200))
    #expect(board.timer(for: 0)?.state == .running(endsAt: at(700)))
  }

  @Test func startingARunningTimerLeavesItAlone() {
    var board = board()
    board.start(step: 0, seconds: 600, now: t0)
    board.start(step: 0, seconds: 600, now: at(100))
    #expect(board.timer(for: 0)?.state == .running(endsAt: at(600)))
  }

  @Test func resettingRemovesTheTimer() {
    var board = board()
    board.start(step: 0, seconds: 60, now: t0)
    board.start(step: 1, seconds: 60, now: t0)
    board.reset(step: 0)
    #expect(board.timers.map(\.step) == [1])
    board.resetAll()
    #expect(board.timers.isEmpty)
  }

  @Test func timersAreListedInStepOrder() {
    var board = board()
    for step in [5, 2, 9] { board.start(step: step, seconds: 60, now: t0) }
    #expect(board.timers.map(\.step) == [2, 5, 9])
    #expect(board.hasRunning)
    board.pause(step: 2, now: t0)
    board.pause(step: 5, now: t0)
    board.pause(step: 9, now: t0)
    #expect(!board.hasRunning)
  }

  @Test func aBoardSurvivesBeingSavedAndRead() throws {
    var board = board()
    board.start(step: 0, seconds: 600, now: t0)
    board.start(step: 1, seconds: 60, now: t0)
    board.pause(step: 1, now: at(10))
    board.start(step: 2, seconds: 30, now: t0)
    board.finishDue(now: at(30))
    let data = try JSONEncoder().encode(board)
    let again = try JSONDecoder().decode(BrewTimerBoard.self, from: data)
    #expect(again == board)
    #expect(again.remaining(of: 0, now: at(100)) == 500)
  }
}
