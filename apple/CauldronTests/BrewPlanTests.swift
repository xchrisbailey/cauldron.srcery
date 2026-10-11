import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Brew plan")
struct BrewPlanTests {
  private func ingredient(_ line: String, section: String? = nil) -> Ingredient {
    let parsed = parseIngredientLine(line)
    return Ingredient(
      section: section, quantity: parsed.quantity, unit: parsed.unit, item: parsed.item,
      note: parsed.note, optional: parsed.optional, alt: parsed.alt, original: line,
      itemKey: ingredientKey(parsed.item))
  }

  private func recipe(servings: Int? = 4) -> BrewRecipe {
    BrewRecipe(
      id: UUID(), title: "Shakshuka", servings: servings,
      steps: [
        Step(section: nil, text: "Warm the olive oil in a skillet.", timerSeconds: nil),
        Step(section: nil, text: "Add the onion and cook 8 minutes.", timerSeconds: 480),
        Step(section: nil, text: "Season and serve.", timerSeconds: nil),
      ],
      ingredients: [
        ingredient("2 tbsp olive oil", section: "Base"),
        ingredient("1 onion, diced"),
        ingredient("3 cloves garlic"),
      ])
  }

  @Test func aStepListsTheIngredientsItMentions() {
    let plan = BrewPlan(recipe(), scale: .servings(4), units: .asWritten)
    #expect(plan.ingredients(for: 0).map(\.text) == ["olive oil"])
    #expect(plan.ingredients(for: 1).map(\.text) == ["onion, diced"])
    #expect(plan.ingredients(for: 2).isEmpty)
  }

  @Test func quantitiesFollowTheChosenScale() {
    let doubled = BrewPlan(recipe(), scale: .servings(8), units: .asWritten)
    #expect(doubled.ingredients(for: 0).first?.amount == "4")
    #expect(doubled.ingredients(for: 0).first?.unit == "tbsp")
    let halved = BrewPlan(recipe(), scale: .servings(2), units: .asWritten)
    #expect(halved.ingredients(for: 0).first?.amount == "1")
    let times = BrewPlan(recipe(servings: nil), scale: .multiplier(3), units: .asWritten)
    #expect(times.ingredients(for: 0).first?.amount == "6")
  }

  @Test func quantitiesFollowTheUnitSystem() {
    let metric = BrewPlan(recipe(), scale: .servings(4), units: .metric)
    #expect(metric.ingredients(for: 0).first?.unit == "ml")
  }

  @Test func theStepsTimerAndPositionComeFromTheRecipe() {
    let plan = BrewPlan(recipe(), scale: .servings(4), units: .asWritten)
    #expect(plan.count == 3)
    #expect(plan.timerSeconds(for: 1) == 480)
    #expect(plan.timerSeconds(for: 0) == nil)
    #expect(plan.timerSeconds(for: 9) == nil)
    #expect(plan.step(at: 9) == nil)
  }

  @Test func aRecordIsCopiedSoLaterEditsDontChangeTheBrew() throws {
    let context = ModelContext(try CauldronStore.container(.inMemory))
    let record = RecipeRecord(title: "Soup")
    context.insert(record)
    record.servings = 2
    record.steps = [Step(section: nil, text: "Stir.", timerSeconds: nil)]
    let brew = BrewRecipe(record)
    record.title = "Changed"
    record.steps = []
    #expect(brew.title == "Soup")
    #expect(brew.id == record.id)
    #expect(brew.steps.map(\.text) == ["Stir."])
    #expect(brew.servings == 2)
  }

  // MARK: Measures in a step

  private func measures(_ text: String) -> [String] {
    StepMeasures.ranges(in: text).map { String(text[$0]) }
  }

  @Test func quantitiesTemperaturesAndTimesInAStepAreFound() {
    #expect(measures("Bake at 180°C for 25 minutes.") == ["180°C", "25 minutes"])
    // The same pattern as the web's, so a mixed number reads as its two halves.
    #expect(measures("Add 1½ cups flour and 2-3 tbsp water.") == ["1", "½ cups", "2-3 tbsp"])
    #expect(measures("Whisk 250 g sugar, 10% milk, and ½ tsp salt.") == ["250 g", "10%", "½ tsp"])
    #expect(measures("Add the onion.").isEmpty)
    #expect(measures("Serves 4").first == "4")
  }

  @Test func aUnitMustBeAWholeWord() {
    #expect(measures("Add 2 eggs and 3 gently") == ["2", "3"])
  }
}
