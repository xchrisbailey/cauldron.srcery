import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

/// Every way of asking for a macro estimate holds its input to the web's limits, so a long
/// recipe's queued estimate isn't refused by the model's input checks.
@MainActor
@Suite("Macro estimate limits in the app")
struct MacroEstimateLimitsAppTests {
  private let container: ModelContainer
  private var context: ModelContext { container.mainContext }

  init() throws {
    container = try CauldronStore.container(.inMemory)
  }

  private func recipe(title: String, servings: Int?, lines: [String]) -> RecipeRecord {
    let recipe = RecipeRecord(title: title)
    recipe.servings = servings
    recipe.ingredients = lines.map {
      Ingredient(
        section: nil, quantity: nil, unit: nil, item: "x", note: nil, optional: false, alt: nil,
        original: $0, itemKey: "x")
    }
    context.insert(recipe)
    return recipe
  }

  private func queuedInput(for recipe: RecipeRecord) async throws -> MacroEstimateInput {
    let estimator = ScriptedEstimator(.macros(Macros(calories: 1, protein: 1, carbs: 1, fat: 1)))
    AIJobQueue.enqueueMacros(for: recipe, in: context)
    await AIJobQueue.drain(in: context, using: estimator)
    return try #require(estimator.inputs.first)
  }

  @Test func aQueuedEstimateCapsTheLineCountAndLength() async throws {
    let long = String(repeating: "y", count: RecipeLimits.line + 200)
    let lines = [long] + (1...(RecipeLimits.ingredients + 50)).map { "\($0) eggs" }
    let input = try await queuedInput(
      for: recipe(title: "Eggs", servings: 4, lines: lines))
    #expect(input.ingredients.count == RecipeLimits.ingredients)
    #expect(input.ingredients.allSatisfy { $0.count <= RecipeLimits.line })
    #expect(input.ingredients.first == String(repeating: "y", count: RecipeLimits.line))
  }

  @Test(arguments: [0, -2, RecipeLimits.servings + 1, 100_000])
  func aQueuedEstimateLeavesOutAYieldOutsideTheLimits(servings: Int) async throws {
    let input = try await queuedInput(
      for: recipe(title: "Eggs", servings: servings, lines: ["6 eggs"]))
    #expect(input.servings == nil)
  }

  @Test func aQueuedEstimateKeepsAYieldInsideTheLimits() async throws {
    for servings in [1, RecipeLimits.servings] {
      let input = try await queuedInput(
        for: recipe(title: "Eggs \(servings)", servings: servings, lines: ["6 eggs"]))
      #expect(input.servings == servings)
    }
  }

  @Test func aQueuedEstimateTrimsBlankLinesAndTheTitle() async throws {
    let input = try await queuedInput(
      for: recipe(title: "  Eggs  ", servings: nil, lines: ["  6 eggs ", "   ", "salt"]))
    #expect(input.title == "Eggs")
    #expect(input.ingredients == ["6 eggs", "salt"])
  }

  @Test func theEditorsAskIsHeldToTheSameLimits() {
    var draft = RecipeDraft()
    draft.title = "  Eggs  "
    draft.servings = "5000"
    draft.setIngredientText(draft.ingredients[0].id, String(repeating: "z", count: 1500))
    let input = draft.estimateInput
    #expect(input?.title == "Eggs")
    #expect(input?.servings == nil)
    #expect(input?.ingredients.first?.count == RecipeLimits.line)
  }
}
