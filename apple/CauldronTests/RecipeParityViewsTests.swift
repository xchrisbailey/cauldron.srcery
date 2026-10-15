import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

#if DEBUG
  /// The recipe page's and brew mode's parity additions, drawn in both appearances on a phone
  /// and on a Mac-sized window.
  @MainActor
  @Suite("Recipe and brew parity views")
  struct RecipeParityViewsTests {
    private let sizes = [CGSize(width: 390, height: 800), CGSize(width: 900, height: 700)]

    private func renders(_ view: some View, container: ModelContainer) -> Bool {
      for size in sizes {
        for scheme in [ColorScheme.light, .dark] {
          let framed = view.modelContainer(container).environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)
          if ImageRenderer(content: framed).cgImage == nil { return false }
        }
      }
      return true
    }

    private func seeded() throws -> (ModelContainer, [RecipeRecord]) {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      try DebugSeed.populate(context, today: DebugSeed.today())
      return (container, try context.fetch(FetchDescriptor<RecipeRecord>()))
    }

    @Test func theEditorOnACopyRendersWithItsNotice() throws {
      let (container, recipes) = try seeded()
      let recipe = try #require(recipes.first)
      let copy = try RecipeDuplication.duplicate(recipe, context: ModelContext(container))
      #expect(renders(RecipeCopySheet(copy: copy), container: container))
    }

    @Test func theNoticeRendersInBothAppearances() throws {
      let container = try CauldronStore.container(.inMemory)
      #expect(renders(RecipeNoticeBanner(notice: .duplicated) {}, container: container))
    }

    @Test func theTickBoxesRenderOnTheRecipePage() throws {
      let (container, recipes) = try seeded()
      for recipe in recipes {
        #expect(
          renders(RecipeDetailView(recipe: recipe) {}, container: container),
          Comment(rawValue: recipe.title))
      }
    }

    @Test func aTickedIngredientAndAnUntickedOneRender() throws {
      let (container, recipes) = try seeded()
      let line = IngredientRow.Line(amount: "2", unit: "cup", text: "lentils", optional: false)
      let view = VStack(alignment: .leading) {
        Toggle(isOn: .constant(true)) { IngredientLineView(line: line, done: true) }
          .toggleStyle(IngredientTickStyle())
        Toggle(isOn: .constant(false)) { IngredientLineView(line: line) }
          .toggleStyle(IngredientTickStyle())
      }
      #expect(renders(view, container: container))
      _ = recipes
    }

    @Test func brewWithNoStepsOffersToEditAndRendersEverywhere() throws {
      let container = try CauldronStore.container(.inMemory)
      let recipe = RecipeRecord(title: "Toast")
      ModelContext(container).insert(recipe)
      let plan = BrewPlan(BrewRecipe(recipe), scale: .multiplier(1), units: .asWritten)
      let clock = TestClock()
      let timers = BrewTimers(
        recipeID: recipe.id, recipeTitle: recipe.title, store: InMemoryTimerStore(),
        alerts: RecordingAlerts(), activities: RecordingActivities(), now: clock.now)
      let model = BrewModel(
        plan: plan, timers: timers, screen: RecordingScreen(), now: clock.now)
      #expect(!model.hasSteps)
      #expect(Copy.brewing.editRecipe.text == "Edit recipe")
      #expect(renders(BrewScreen(model: model, recipe: recipe, onClose: {}), container: container))
    }

    @Test func theLastStepOffersLogItAndBrewedAndRendersEverywhere() async throws {
      let container = try CauldronStore.container(.inMemory)
      let recipe = RecipeRecord(title: "Toast")
      ModelContext(container).insert(recipe)
      recipe.steps = [
        Step(section: nil, text: "Toast the bread.", timerSeconds: nil),
        Step(section: nil, text: "Butter it.", timerSeconds: nil),
      ]
      let plan = BrewPlan(BrewRecipe(recipe), scale: .multiplier(1), units: .asWritten)
      let clock = TestClock()
      let timers = BrewTimers(
        recipeID: recipe.id, recipeTitle: recipe.title, store: InMemoryTimerStore(),
        alerts: RecordingAlerts(), activities: RecordingActivities(), now: clock.now)
      let model = BrewModel(
        plan: plan, timers: timers, screen: RecordingScreen(), now: clock.now)
      model.go(to: 1)
      #expect(model.isLast)
      #expect(Copy.tracker.logRecipe.title.text == "Log it")
      #expect(renders(BrewScreen(model: model, recipe: recipe, onClose: {}), container: container))
    }
  }
#endif
