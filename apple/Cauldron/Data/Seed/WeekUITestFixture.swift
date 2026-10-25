#if DEBUG
  import CauldronKit
  import Foundation
  import SwiftData

  enum WeekUITestFixture {
    /// Fixture selection never enables a store: the explicit isolated UI-test contract is required too.
    static func populateIfRequested(
      mode: CauldronStore.Mode, context: ModelContext,
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
      guard mode == .inMemory,
        environment[CauldronStore.uiTestInMemoryEnvironmentKey] == "1",
        let scenario = environment["CAULDRON_UI_TEST_WEEK"],
        ["breakfast", "dinner"].contains(scenario)
      else { return }
      let today = try DebugSeed.today()
      let start = today.startOfWeek(startingOn: .standard)
      context.insert(TargetsRecord(calories: 2000, protein: 140, carbs: 240, fat: 60))
      var firstRecipe: RecipeRecord?
      for index in 0..<7 {
        let recipe: RecipeRecord
        if index == 1, let firstRecipe {
          recipe = firstRecipe
        } else {
          recipe = RecipeRecord(
            title: index == 0
              ? "Breakfast bowl with yoghurt, berries and toasted seeds"
              : "Planned recipe \(index + 1)")
          recipe.servings = 1
          recipe.macros = Macros(calories: 500, protein: 30, carbs: 60, fat: 15)
          recipe.macrosSource = .manual
          context.insert(recipe)
          if index == 0 { firstRecipe = recipe }
        }
        let batch = try WeekPlan.createBatch(
          recipe: recipe, weekStart: start, totalServings: index == 0 ? 3 : 1, in: context)
        let entry = PlanEntryRecord(
          day: today, slot: scenario == "dinner" ? .dinner : .breakfast,
          title: recipe.title, servings: 1)
        context.insert(entry)
        entry.recipe = recipe
        entry.batch = batch
      }
      try context.save()
    }
  }
#endif
