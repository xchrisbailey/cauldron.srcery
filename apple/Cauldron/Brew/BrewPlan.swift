import CauldronKit
import Foundation

/// The recipe as brewing sees it: a copy, so editing or syncing the recipe mid-cook doesn't
/// change the steps under the cook's hands.
struct BrewRecipe: Equatable, Sendable {
  var id: UUID
  var title: String
  var servings: Int?
  var steps: [Step]
  var ingredients: [Ingredient]

  init(id: UUID, title: String, servings: Int?, steps: [Step], ingredients: [Ingredient]) {
    self.id = id
    self.title = title
    self.servings = servings
    self.steps = steps
    self.ingredients = ingredients
  }

  init(_ record: RecipeRecord) {
    self.init(
      id: record.id, title: record.title, servings: record.servings, steps: record.steps,
      ingredients: record.ingredients)
  }
}

/// What each step of a brew shows: its text, its timer, and the ingredients it mentions at the
/// cook's scale and in their unit system (`stepIngredients` in CauldronKit).
struct BrewPlan: Sendable {
  let recipe: BrewRecipe
  let scale: Scale
  let units: UnitSystemChoice
  private let matched: [[Int]]

  init(_ recipe: BrewRecipe, scale: Scale, units: UnitSystemChoice) {
    self.recipe = recipe
    self.scale = scale
    self.units = units
    matched = stepIngredients(recipe.steps, recipe.ingredients)
  }

  var count: Int { recipe.steps.count }

  func step(at index: Int) -> Step? {
    recipe.steps.indices.contains(index) ? recipe.steps[index] : nil
  }

  func timerSeconds(for index: Int) -> Int? { step(at: index)?.timerSeconds }

  /// The step's ingredients, scaled and in the chosen units. Section headings are left out:
  /// the cook is looking at one step.
  func ingredients(for index: Int) -> [IngredientRow.Line] {
    guard matched.indices.contains(index) else { return [] }
    let lines = matched[index].compactMap {
      recipe.ingredients.indices.contains($0) ? recipe.ingredients[$0] : nil
    }
    .map { line -> Ingredient in
      var line = line
      line.section = nil
      return line
    }
    let factor = scale.factor(recipeServings: recipe.servings)
    return IngredientRow.rows(lines, factor: factor, system: units).compactMap {
      if case .line(let line) = $0 { line } else { nil }
    }
  }
}

/// The numbers, temperatures and times in a step's text, which are set in Geist Mono.
enum StepMeasures {
  private static let pattern =
    #"(?:\d+(?:[.,]\d+)?|[½¼¾⅓⅔⅛])(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?"#
    + #"(?:\s*(?:°\s?[CF]|%|(?:kg|g|ml|l|oz|lbs?|cups?|tbsp|tsp|minutes?|mins?|hours?|hrs?|seconds?|secs?)\b))?"#
  private static let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

  static func ranges(in text: String) -> [Range<String.Index>] {
    let whole = NSRange(text.startIndex..., in: text)
    return (regex?.matches(in: text, range: whole) ?? []).compactMap { Range($0.range, in: text) }
  }
}
