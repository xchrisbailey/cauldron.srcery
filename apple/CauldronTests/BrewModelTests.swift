import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Brew model")
struct BrewModelTests {
  private let clock = TestClock()
  private let alerts = RecordingAlerts()
  private let activities = RecordingActivities()
  private let store = InMemoryTimerStore()
  private let screen = RecordingScreen()

  private func recipe(steps: [Step]? = nil) -> BrewRecipe {
    BrewRecipe(
      id: UUID(), title: "Soup", servings: 4,
      steps: steps ?? [
        Step(section: nil, text: "Chop.", timerSeconds: nil),
        Step(section: nil, text: "Simmer 10 minutes.", timerSeconds: 600),
        Step(section: nil, text: "Rest 5 minutes.", timerSeconds: 300),
        Step(section: nil, text: "Serve.", timerSeconds: nil),
      ],
      ingredients: [])
  }

  private func model(_ recipe: BrewRecipe? = nil) -> BrewModel {
    let recipe = recipe ?? self.recipe()
    return BrewModel(
      plan: BrewPlan(recipe, scale: .servings(4), units: .asWritten),
      timers: BrewTimers(
        recipeID: recipe.id, recipeTitle: recipe.title, store: store, alerts: alerts,
        activities: activities, now: clock.now),
      screen: screen, now: clock.now)
  }

  @Test func inMemoryLaunchUsesEphemeralTimerAndNoNotificationServices() async {
    let recipe = recipe()
    let plan = BrewPlan(recipe, scale: .servings(4), units: .asWritten)
    let model = BrewLive.model(for: plan, mode: .inMemory)
    await model.begin()
    #expect(model.timers.notificationsRefused)
    model.next()
    await model.toggleTimer()
    #expect(model.timers.timer(for: 1) != nil)

    let nextLaunch = BrewLive.model(for: plan, mode: .inMemory)
    await nextLaunch.begin()
    #expect(nextLaunch.timers.timer(for: 1) == nil)
    #expect(nextLaunch.timers.notificationsRefused)
  }

  // MARK: Moving

  @Test func theCookMovesOneStepAtATimeAndStopsAtTheEnds() {
    let model = model()
    #expect(model.index == 0 && !model.canGoBack && model.canGoForward)
    model.previous()
    #expect(model.index == 0)
    model.next()
    model.next()
    model.next()
    #expect(model.index == 3 && model.isLast && !model.canGoForward)
    model.next()
    #expect(model.index == 3)
    model.previous()
    #expect(model.index == 2)
  }

  @Test func goingToAStepStaysInRange() {
    let model = model()
    model.go(to: 99)
    #expect(model.index == 3)
    model.go(to: -4)
    #expect(model.index == 0)
    model.go(to: 2)
    #expect(model.index == 2)
  }

  @Test func theProgressIsTheStepsDoneOverTheCount() {
    let model = model()
    #expect(model.progress == 0.25)
    model.next()
    #expect(model.progress == 0.5)
  }

  @Test func aRecipeWithNoStepsHasNothingToBrew() {
    let model = model(recipe(steps: []))
    #expect(model.hasSteps == false)
    #expect(model.step == nil)
    #expect(model.progress == 0)
    model.next()
    #expect(model.index == 0)
  }

  // MARK: The step's timer

  @Test func theTimerButtonStartsPausesResumesAndResetsTheStepsTimer() async {
    let model = model()
    model.go(to: 1)
    #expect(model.timerAction == .start)
    await model.toggleTimer()
    #expect(model.timerAction == .pause)
    #expect(model.timers.timer(for: 1)?.totalSeconds == 600)
    await model.toggleTimer()
    #expect(model.timerAction == .resume)
    await model.toggleTimer()
    #expect(model.timerAction == .pause)
    clock.advance(601)
    await model.timers.refresh()
    #expect(model.timerAction == .reset)
    await model.toggleTimer()
    #expect(model.timerAction == .start)
    #expect(model.timers.timer(for: 1) == nil)
  }

  @Test func aStepWithNoTimerHasNoTimerButton() async {
    let model = model()
    #expect(model.timerAction == nil)
    await model.toggleTimer()
    #expect(model.timers.board.timers.isEmpty)
  }

  @Test func timersKeepRunningWhileTheCookMovesToOtherSteps() async {
    let model = model()
    model.go(to: 1)
    await model.toggleTimer()
    model.go(to: 2)
    await model.toggleTimer()
    model.go(to: 0)
    #expect(model.timers.board.timers.map(\.step) == [1, 2])
    #expect(model.otherTimers.map(\.step) == [1, 2])
    model.go(to: 1)
    #expect(model.otherTimers.map(\.step) == [2])
    #expect(alerts.scheduled.count == 2)
  }

  @Test func addingAMinuteExtendsTheCurrentStepsTimer() async {
    let model = model()
    model.go(to: 1)
    await model.toggleTimer()
    await model.addMinute()
    #expect(model.timers.timer(for: 1)?.totalSeconds == 660)
  }

  // MARK: The screen

  @Test func theScreenStaysOnWhileBrewingAndIsRestored() async {
    let model = model()
    await model.begin()
    model.end()
    #expect(screen.states == [true, false])
  }

  @Test func beginningPicksUpTimersLeftRunning() async {
    let first = model(recipe())
    first.go(to: 1)
    await first.toggleTimer()
    // The same recipe again, as after a relaunch.
    clock.advance(60)
    let again = BrewModel(
      plan: first.plan,
      timers: BrewTimers(
        recipeID: first.plan.recipe.id, recipeTitle: "Soup", store: store, alerts: alerts,
        activities: activities, now: clock.now),
      screen: screen, now: clock.now)
    await again.begin()
    #expect(again.timers.remaining(of: 1) == 540)
  }

  // MARK: Finishing

  @Test func brewedMarksTheRecipeCookedThenEndsTheTimers() async throws {
    let model = model()
    model.go(to: 1)
    await model.toggleTimer()
    model.go(to: 3)
    clock.advance(5)
    var marked = 0
    let finished = try await model.finish { marked += 1 }
    #expect(finished)
    #expect(marked == 1)
    #expect(model.timers.board.timers.isEmpty)
    #expect(activities.ended.count == 1)
  }

  @Test func aSecondTapRightAfterMovingToTheLastStepDoesNotFinish() async throws {
    let model = model()
    model.go(to: 3)
    var marked = 0
    // The "Brewed" button took the place of "Next step" a moment ago.
    clock.advance(0.3)
    let finished = try await model.finish { marked += 1 }
    #expect(!finished)
    #expect(marked == 0)
    clock.advance(1)
    #expect(try await model.finish { marked += 1 })
    #expect(marked == 1)
  }

  @Test func ifRecordingFailsTheTimersKeepRunningAndTheErrorIsPassedOn() async {
    struct Boom: Error {}
    let model = model()
    model.go(to: 1)
    await model.toggleTimer()
    model.go(to: 3)
    clock.advance(5)
    await #expect(throws: Boom.self) {
      try await model.finish { throw Boom() }
    }
    #expect(model.timers.board.timers.count == 1)
    #expect(activities.ended.isEmpty)
  }
}
