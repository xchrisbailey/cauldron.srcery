import CauldronKit
import SwiftData
import SwiftUI
import Testing
import UserNotifications

@testable import Cauldron

#if DEBUG
  @MainActor
  @Suite("Brew views")
  struct BrewViewsTests {
    private let clock = TestClock()

    private func session(
      _ recipe: RecipeRecord, container: ModelContainer, store: InMemoryTimerStore = .init()
    ) -> BrewSession {
      let plan = BrewPlan(BrewRecipe(recipe), scale: .servings(4), units: .asWritten)
      let timers = BrewTimers(
        recipeID: recipe.id, recipeTitle: recipe.title, store: store, alerts: RecordingAlerts(),
        activities: RecordingActivities(), now: clock.now)
      return BrewSession(
        model: BrewModel(plan: plan, timers: timers, screen: RecordingScreen(), now: clock.now),
        recipe: recipe)
    }

    private func renders(_ view: some View) -> Bool {
      ImageRenderer(content: view.frame(width: 390, height: 800)).cgImage != nil
    }

    @Test func everyStepOfEverySeededRecipeRendersInBothAppearances() async throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      try DebugSeed.populate(context, today: DebugSeed.today())
      let recipes = try context.fetch(FetchDescriptor<RecipeRecord>())
      for recipe in recipes {
        let session = session(recipe, container: container)
        for index in 0..<max(1, session.model.plan.count) {
          session.model.go(to: index)
          if session.model.timerSeconds != nil { await session.model.toggleTimer() }
          for scheme in [ColorScheme.light, .dark] {
            let view = BrewScreen(model: session.model, recipe: recipe, onClose: {})
              .modelContainer(container)
              .environment(\.colorScheme, scheme)
            #expect(renders(view), "\(recipe.title) step \(index + 1) in \(scheme)")
          }
        }
      }
    }

    @Test func aRecipeWithNoStepsRenders() throws {
      let container = try CauldronStore.container(.inMemory)
      let recipe = RecipeRecord(title: "Toast")
      ModelContext(container).insert(recipe)
      let session = session(recipe, container: container)
      let view = BrewScreen(model: session.model, recipe: recipe, onClose: {})
        .modelContainer(container)
      #expect(renders(view))
    }

    @Test func aStepsTextSetsItsMeasuresApart() {
      let text = BrewStepText.attributed("Bake at 180°C for 25 minutes.", size: 20)
      let mono = Font.brand(.quantity, size: 20 * 0.92)
      let measures = text.runs.filter { $0.font == mono }.map { String(text[$0.range].characters) }
      #expect(measures == ["180°C", "25 minutes"])
      #expect(String(text.characters) == "Bake at 180°C for 25 minutes.")
    }

    @Test func theTimerButtonsAreLabelledFromTheCopyModule() {
      #expect(BrewTimerRing.label(.start) == "Start timer")
      #expect(BrewTimerRing.label(.pause) == "Pause")
      #expect(BrewTimerRing.label(.resume) == "Resume")
      #expect(BrewTimerRing.label(.reset) == "Reset")
    }

    @Test func aBrewRequestRemembersTheScale() {
      let id = UUID()
      #expect(BrewRequest(recipeID: id, scale: .servings(6)).scale == .servings(6))
      #expect(BrewRequest(recipeID: id, scale: .multiplier(1.5)).scale == .multiplier(1.5))
    }

    @Test func aSessionIsOnlyMadeForARecipeThatExists() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let live = RecipeRecord(title: "Soup")
      let gone = RecipeRecord(title: "Stew")
      context.insert(live)
      context.insert(gone)
      gone.deletedAt = .now
      #expect(BrewSession.make(recipeID: live.id, scale: .servings(2), context: context) != nil)
      #expect(BrewSession.make(recipeID: gone.id, scale: .servings(2), context: context) == nil)
      #expect(BrewSession.make(recipeID: UUID(), scale: .servings(2), context: context) == nil)
    }

    @Test func aSessionTakesTheUnitSystemFromSettings() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let recipe = RecipeRecord(title: "Soup")
      context.insert(recipe)
      let preferences = PreferencesRecord()
      preferences.unitSystem = .metric
      context.insert(preferences)
      let session = BrewSession.make(recipe: recipe, scale: .servings(2), context: context)
      #expect(session.model.plan.units == .metric)
    }

    // MARK: Live services

    @Test func notificationAuthorizationMapsToThePermissionTheTimersUse() {
      #expect(LiveBrewAlerts.permission(.notDetermined) == .notDetermined)
      #expect(LiveBrewAlerts.permission(.authorized) == .granted)
      #expect(LiveBrewAlerts.permission(.provisional) == .granted)
      #expect(LiveBrewAlerts.permission(.denied) == .denied)
    }

    @Test func runningTimersAreKeptOnThisDeviceAndSurviveANewStore() throws {
      let suite = "BrewStoreTests-\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      var board = BrewTimerBoard(recipeID: UUID(), recipeTitle: "Soup")
      board.start(step: 1, seconds: 600, now: clock.date)
      UserDefaultsBrewTimerStore(defaults: defaults).save(board)
      let again = UserDefaultsBrewTimerStore(defaults: defaults)
      #expect(again.load(recipeID: board.recipeID) == board)
      #expect(again.load(recipeID: UUID()) == nil)
      again.remove(recipeID: board.recipeID)
      #expect(again.load(recipeID: board.recipeID) == nil)
    }
  }
#endif

#if os(iOS)
  @Suite("Live Activity state")
  struct BrewActivityStateTests {
    private let end = Date(timeIntervalSince1970: 1_000_600)

    private func state(_ phase: BrewActivityState.Phase) -> BrewActivityState {
      BrewActivityState(
        id: "brew.x.1", recipeTitle: "Soup", stepNumber: 2, label: "Step 2", totalSeconds: 600,
        phase: phase)
    }

    @Test func aRunningTimerCarriesItsEndNotACounter() {
      let running = state(.running(endsAt: end))
      #expect(running.contentState.endsAt == end)
      #expect(!running.contentState.finished)
      #expect(running.attributes.key == "brew.x.1")
      #expect(running.attributes.totalSeconds == 600)
      #expect(running.attributes.stepNumber == 2)
    }

    @Test func aPausedTimerCarriesWhatIsLeft() {
      let paused = state(.paused(remaining: 240)).contentState
      #expect(paused.endsAt == nil)
      #expect(paused.remainingSeconds == 240)
      #expect(!paused.finished)
    }

    @Test func aFinishedTimerSaysSo() {
      let done = state(.finished).contentState
      #expect(done.finished)
      #expect(done.endsAt == nil)
    }
  }
#endif
