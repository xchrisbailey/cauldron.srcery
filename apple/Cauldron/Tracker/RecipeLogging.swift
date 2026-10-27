import CauldronKit
import Foundation

/// The meal the hour suggests, for logging from outside the diary.
func suggestedSlot(hour: Int) -> MealSlot {
  switch hour {
  case ..<11: .breakfast
  case ..<15: .lunch
  case ..<21: .dinner
  default: .snack
  }
}

/// A recipe about to be logged: how many servings, and (outside the diary's add sheet, where
/// the meal and day are already chosen) which meal and day. Servings are text while edited.
struct RecipeLogDraft: Equatable {
  var servings = "1"
  var slot: MealSlot
  var day: LocalDate

  /// The shortcuts beside the stepper.
  static let quickServings: [Double] = [0.5, 1, 1.5, 2]
  static let step = EntryDraft.servingStep

  init(slot: MealSlot, day: LocalDate, servings: Double = 1) {
    self.slot = slot
    self.day = day
    self.servings = showNumber(servings, digits: 2)
  }

  /// The servings typed, when they are above 0 and no more than a day can hold.
  var servingsValue: Double? {
    guard let value = parseNumber(servings), value > 0, value <= Double(TrackerLimits.servings)
    else { return nil }
    return value
  }

  var servingsError: CopyString? {
    servingsValue == nil ? Copy.validation.numberBetween(0, Double(TrackerLimits.servings)) : nil
  }

  mutating func nudge(by amount: Double) {
    let current = parseNumber(servings) ?? 1
    servings = showNumber(max(Self.step, current + amount), digits: 2)
  }

  /// What logging adds to the day: the recipe's per-serving numbers times the servings. Unknown
  /// numbers add nothing.
  func totals(of recipe: RecipeRecord) -> MacroTotals {
    entryTotals(macros: recipe.macros, servings: servingsValue ?? 0)
  }

  /// The entry to log: the recipe's per-serving numbers copied now, so later edits to the recipe
  /// leave the day alone, and a link to the recipe. A recipe missing numbers is logged with the
  /// gap showing.
  func entry(for recipe: RecipeRecord) -> NewEntry? {
    guard let servings = servingsValue else { return nil }
    return NewEntry(
      name: recipe.title, servings: servings, macros: recipe.macros, source: .recipe,
      recipe: recipe)
  }
}

enum RecipePicker {
  /// How many matches the picker lists.
  static let limit = 50

  /// The recipes to offer: not banished, narrowed by a search, by title.
  static func matches(
    _ recipes: [RecipeRecord], query: String, index: RecipeSearchIndex? = nil
  ) -> [RecipeRecord] {
    found(recipes, query: query, index: index).map(\.recipe)
  }

  /// `matches`, with how each recipe matched: exact ones by title, then close ones by title.
  /// The limit counts across both.
  static func found(
    _ recipes: [RecipeRecord], query: String, index: RecipeSearchIndex? = nil
  ) -> [RecipeMatch] {
    Array(
      RecipeLibrary.visibleMatches(recipes, matching: query, sort: .title, index: index)
        .prefix(limit))
  }

  /// "320 kcal a serving · 25 min", or "No calories yet".
  static func detail(_ recipe: RecipeRecord) -> String {
    let times = RecipeTimes(recipe)
    let calories =
      recipe.calories.map {
        "\(MacroMeter.whole($0)) \(Copy.tracker.macros.calories.text) \(Copy.tracker.logRecipe.aServing.text)"
      } ?? Copy.tracker.logRecipe.noNumbers.text
    return [calories, times.total].compactMap { $0 }.joined(separator: " · ")
  }
}
