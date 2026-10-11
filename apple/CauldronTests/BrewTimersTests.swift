import Foundation
import Testing

@testable import Cauldron

@MainActor
@Suite("Brew timers")
struct BrewTimersTests {
  private let recipeID = UUID()
  private let clock = TestClock()
  private let alerts = RecordingAlerts()
  private let activities = RecordingActivities()
  private let store = InMemoryTimerStore()

  private func timers() -> BrewTimers {
    BrewTimers(
      recipeID: recipeID, recipeTitle: "Shakshuka", store: store, alerts: alerts,
      activities: activities, now: clock.now)
  }

  private func id(_ step: Int) -> String { "brew.\(recipeID.uuidString).\(step)" }

  // MARK: Starting

  @Test func startingATimerSchedulesItsNotificationForTheEndAndShowsAnActivity() async {
    let timers = timers()
    await timers.start(step: 2, seconds: 600)
    #expect(
      alerts.scheduled == [
        BrewAlert(
          id: id(2), title: "Time's up", body: "Shakshuka: the step 3 timer is done.",
          fireAt: clock.date.addingTimeInterval(600))
      ])
    #expect(
      activities.shown == [
        BrewActivityState(
          id: id(2), recipeTitle: "Shakshuka", stepNumber: 3, label: "Step 3", totalSeconds: 600,
          phase: .running(endsAt: clock.date.addingTimeInterval(600)))
      ])
    #expect(timers.remaining(of: 2) == 600)
  }

  @Test func theFirstTimerAsksForPermissionAndLaterOnesDont() async {
    let timers = timers()
    await timers.start(step: 0, seconds: 60)
    await timers.start(step: 1, seconds: 120)
    #expect(alerts.requests == 1)
    #expect(alerts.scheduled.map(\.id) == [id(0), id(1)])
  }

  @Test func twoTimersRunAtOnceEachWithItsOwnNotificationAndActivity() async {
    let timers = timers()
    await timers.start(step: 1, seconds: 300)
    clock.advance(30)
    await timers.start(step: 4, seconds: 900)
    #expect(
      alerts.scheduled.map(\.fireAt) == [
        clock.date.addingTimeInterval(-30 + 300), clock.date.addingTimeInterval(900),
      ])
    #expect(Set(activities.shown.map(\.id)) == [id(1), id(4)])
    #expect(timers.remaining(of: 1) == 270)
    #expect(timers.remaining(of: 4) == 900)
  }

  @Test func aCookWhoAlreadyAllowedNotificationsIsNotAskedAgain() async {
    alerts.current = .granted
    await timers().start(step: 0, seconds: 60)
    #expect(alerts.requests == 0)
    #expect(alerts.scheduled.count == 1)
  }

  @Test func refusedNotificationsStillShowTheActivityAndTheScreenSaysSo() async {
    alerts.answer = .denied
    let timers = timers()
    await timers.start(step: 0, seconds: 60)
    #expect(alerts.scheduled.isEmpty)
    #expect(timers.notificationsRefused)
    #expect(activities.shown.count == 1)
    // And a later timer doesn't ask again.
    await timers.start(step: 1, seconds: 60)
    #expect(alerts.requests == 1)
  }

  // MARK: Changing a timer

  @Test func pausingCancelsTheNotificationAndShowsWhatIsLeft() async {
    let timers = timers()
    await timers.start(step: 0, seconds: 600)
    clock.advance(100)
    await timers.pause(step: 0)
    #expect(alerts.cancelled == [id(0)])
    #expect(
      activities.shown.last?.phase == .paused(remaining: 500))
    // Time passing while paused doesn't change it.
    clock.advance(1_000)
    #expect(timers.remaining(of: 0) == 500)
  }

  @Test func resumingSchedulesTheNotificationFromNow() async {
    let timers = timers()
    await timers.start(step: 0, seconds: 600)
    clock.advance(100)
    await timers.pause(step: 0)
    clock.advance(1_000)
    await timers.resume(step: 0)
    #expect(alerts.scheduled.last?.fireAt == clock.date.addingTimeInterval(500))
    #expect(
      activities.shown.last?.phase == .running(endsAt: clock.date.addingTimeInterval(500)))
  }

  @Test func addingAMinuteMovesTheNotificationAndTheActivity() async {
    let timers = timers()
    await timers.start(step: 0, seconds: 120)
    await timers.addMinute(step: 0)
    #expect(alerts.scheduled.last?.fireAt == clock.date.addingTimeInterval(180))
    #expect(activities.shown.last?.totalSeconds == 180)
    #expect(activities.shown.last?.phase == .running(endsAt: clock.date.addingTimeInterval(180)))
  }

  @Test func resettingCancelsTheNotificationAndEndsTheActivity() async {
    let timers = timers()
    await timers.start(step: 0, seconds: 120)
    await timers.reset(step: 0)
    #expect(alerts.cancelled == [id(0)])
    #expect(activities.ended == [id(0)])
    #expect(timers.timer(for: 0) == nil)
  }

  @Test func endingAllTimersCancelsAndEndsEach() async {
    let timers = timers()
    await timers.start(step: 0, seconds: 60)
    await timers.start(step: 3, seconds: 60)
    await timers.resetAll()
    #expect(Set(alerts.cancelled) == [id(0), id(3)])
    #expect(Set(activities.ended) == [id(0), id(3)])
    #expect(timers.board.timers.isEmpty)
    #expect(store.boards[recipeID] == nil)
  }

  // MARK: Finishing

  @Test func aTimerThatRanOutIsFinishedOnTheNextRefreshWithoutSchedulingAnything() async {
    let timers = timers()
    await timers.start(step: 0, seconds: 60)
    await timers.start(step: 1, seconds: 600)
    let scheduled = alerts.scheduled.count
    clock.advance(61)
    let finished = await timers.refresh()
    #expect(finished == [0])
    #expect(timers.timer(for: 0)?.state == .done)
    #expect(activities.shown.last?.phase == .finished)
    #expect(alerts.scheduled.count == scheduled)
    #expect(await timers.refresh().isEmpty)
  }

  // MARK: Surviving the app

  @Test func everyChangeIsSavedAndAnEmptyBoardIsNot() async {
    let timers = timers()
    await timers.start(step: 0, seconds: 60)
    #expect(store.boards[recipeID]?.timer(for: 0) != nil)
    await timers.reset(step: 0)
    #expect(store.boards[recipeID] == nil)
  }

  @Test func aRelaunchFindsRunningTimersWhereTheyWereAndSchedulesThemAgain() async {
    let first = timers()
    await first.start(step: 0, seconds: 600)
    await first.start(step: 2, seconds: 60)
    clock.advance(120)
    alerts.calls = []
    activities.calls = []

    let second = timers()
    await second.restore()
    #expect(second.timer(for: 0)?.state == .running(endsAt: clock.date.addingTimeInterval(480)))
    #expect(second.timer(for: 2)?.state == .done)
    #expect(second.remaining(of: 0) == 480)
    #expect(alerts.scheduled.map(\.id) == [id(0)])
    #expect(
      activities.shown.map(\.phase) == [
        .running(endsAt: clock.date.addingTimeInterval(480)), .finished,
      ])
  }

  @Test func aRelaunchWithNothingSavedStartsEmpty() async {
    let timers = timers()
    await timers.restore()
    #expect(timers.board.timers.isEmpty)
    #expect(activities.calls.isEmpty)
  }

  @Test func timersOfAnotherRecipeAreNotMixedIn() async {
    let other = BrewTimers(
      recipeID: UUID(), recipeTitle: "Soup", store: store, alerts: alerts,
      activities: activities, now: clock.now)
    await other.start(step: 0, seconds: 60)
    let mine = timers()
    await mine.restore()
    #expect(mine.board.timers.isEmpty)
  }

  @Test func theRestoredPermissionIsKnownWithoutAsking() async {
    alerts.current = .denied
    let timers = timers()
    await timers.restore()
    #expect(timers.notificationsRefused)
    #expect(alerts.requests == 0)
  }
}
