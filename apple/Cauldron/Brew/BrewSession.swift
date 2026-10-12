import CauldronKit
import Foundation
import SwiftData

/// One brew in progress: its model, and the recipe it will mark cooked.
struct BrewSession: Identifiable {
  let id = UUID()
  let model: BrewModel
  let recipe: RecipeRecord

  /// Starts brewing a recipe at a scale, with the unit system from Settings.
  @MainActor
  static func make(recipe: RecipeRecord, scale: Scale, context: ModelContext) -> BrewSession {
    let units = (try? context.current(PreferencesRecord.self))?.unitSystem ?? .asWritten
    let plan = BrewPlan(BrewRecipe(recipe), scale: scale, units: units)
    return BrewSession(model: BrewLive.model(for: plan), recipe: recipe)
  }

  /// The same, looking the recipe up; nil when it has been banished or doesn't exist.
  @MainActor
  static func make(recipeID: UUID, scale: Scale, context: ModelContext) -> BrewSession? {
    var lookup = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == recipeID })
    lookup.fetchLimit = 1
    guard let recipe = (try? context.fetch(lookup))?.first, !recipe.isBanished else { return nil }
    return make(recipe: recipe, scale: scale, context: context)
  }
}
