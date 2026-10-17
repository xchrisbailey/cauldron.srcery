import CauldronKit
import SwiftData
import Testing

@testable import Cauldron

/// The unit choice is one remembered preference, which the recipe page writes and brew reads.
@MainActor
@Suite("Unit preference")
struct UnitPreferenceTests {
  private let context: ModelContext

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  private func stored() throws -> [PreferencesRecord] {
    try context.fetch(FetchDescriptor<PreferencesRecord>())
  }

  @Test func withNoPreferenceTheRecipeIsAsWritten() throws {
    #expect(UnitPreference.current(try stored()) == .asWritten)
    #expect(UnitPreference.current(in: context) == .asWritten)
  }

  @Test func choosingMakesThePreferenceAndRemembersIt() throws {
    UnitPreference.set(.metric, preferences: try stored(), in: context)
    #expect(try stored().count == 1)
    #expect(UnitPreference.current(in: context) == .metric)
    #expect(UnitPreference.current(try stored()) == .metric)
  }

  @Test func choosingAgainChangesTheOneRecordAndLeavesTheWeekStartAlone() throws {
    WeekStartPreference.set(.sunday, preferences: try stored(), in: context)
    UnitPreference.set(.us, preferences: try stored(), in: context)
    UnitPreference.set(.metric, preferences: try stored(), in: context)
    let records = try stored()
    #expect(records.count == 1)
    #expect(records.first?.unitSystem == .metric)
    #expect(WeekStartPreference.current(records) == .sunday)
  }

  @Test func brewStartsInTheUnitsChosenOnTheRecipePage() throws {
    let recipe = RecipeRecord(title: "Soup")
    context.insert(recipe)
    #expect(
      BrewSession.make(recipe: recipe, scale: .servings(2), context: context).model.plan.units
        == .asWritten)
    UnitPreference.set(.us, preferences: try stored(), in: context)
    #expect(
      BrewSession.make(recipe: recipe, scale: .servings(2), context: context).model.plan.units
        == .us)
    #expect(
      BrewSession.make(recipeID: recipe.id, scale: .servings(2), context: context)?
        .model.plan.units == .us)
  }
}
