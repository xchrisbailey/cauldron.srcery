import CauldronKit
import Foundation

// What the recipe screens print, worked out apart from the views so it can be tested.

/// One row of a recipe's ingredient list at a scale and in a unit system.
enum IngredientRow: Hashable {
  case heading(String)
  case line(Line)

  struct Line: Hashable {
    /// The scaled amount, in Geist Mono; nil for a line with no quantity.
    var amount: String?
    /// The unit beside it, quieter.
    var unit: String?
    /// The item and its note.
    var text: String
    var optional: Bool
  }

  static func rows(
    _ ingredients: [Ingredient], factor: Double, system: UnitSystemChoice
  ) -> [IngredientRow] {
    withHeadings(ingredients).map { row -> IngredientRow in
      switch row {
      case .heading(let name):
        return .heading(name)
      case .line(let ingredient):
        let measure = ingredient.quantity.map {
          displayMeasure($0, unit: ingredient.unit, factor: factor, system: system)
        }
        let text = [ingredient.item, ingredient.note].compactMap { $0 }.filter { !$0.isEmpty }
        return .line(
          Line(
            amount: measure?.amount, unit: measure?.unit, text: text.joined(separator: ", "),
            optional: ingredient.optional))
      }
    }
  }
}

/// What a library card shows.
struct RecipeCardInfo {
  let title: String
  /// Total time, or nil when none is known.
  let time: String?
  /// Up to two tags.
  let tags: [TagChip]
  let macros: MacroLine?

  init(_ recipe: RecipeRecord) {
    title = recipe.title
    time = RecipeTimes.label(
      recipeMinutes(
        totalMinutes: recipe.totalMinutes, prepMinutes: recipe.prepMinutes,
        cookMinutes: recipe.cookMinutes))
    tags = TagChip.chips(recipe, limit: 2)
    macros = macroLine(recipe.macros)
  }
}

/// A tag as a recipe shows it; the kind picks its colour.
struct TagChip: Hashable {
  let name: String
  let kind: TagKind

  /// The recipe's tags by name, up to `limit` of them.
  static func chips(_ recipe: RecipeRecord, limit: Int = .max) -> [TagChip] {
    (recipe.tags ?? []).map { TagChip(name: $0.name, kind: $0.kind) }
      .sorted { $0.name < $1.name }.prefix(limit).map { $0 }
  }
}

/// One row of a recipe's method.
enum StepRow: Hashable {
  case heading(String)
  case step(number: Int, text: String, timer: String?)

  /// Steps numbered straight through, with a heading before each new section.
  static func rows(_ steps: [Step]) -> [StepRow] {
    var rows: [StepRow] = []
    var section: String?
    for (index, step) in steps.enumerated() {
      if step.section != section {
        section = step.section
        if let section { rows.append(.heading(section)) }
      }
      rows.append(
        .step(number: index + 1, text: step.text, timer: step.timerSeconds.map(formatTimer)))
    }
    return rows
  }
}

/// The times on a recipe's page.
struct RecipeTimes {
  let total: String?
  let prep: String?
  let cook: String?

  init(_ recipe: RecipeRecord) {
    total = Self.label(
      recipeMinutes(
        totalMinutes: recipe.totalMinutes, prepMinutes: recipe.prepMinutes,
        cookMinutes: recipe.cookMinutes))
    prep = Self.label(recipe.prepMinutes)
    cook = Self.label(recipe.cookMinutes)
  }

  /// "25 min", "1 h 30 min"; nil for an unknown or zero time.
  static func label(_ minutes: Int?) -> String? {
    guard let minutes, minutes > 0 else { return nil }
    return formatTimer(minutes * 60)
  }
}

enum RecipeScale {
  /// "serves 4", or "×1 ½" for a recipe with no servings.
  static func label(_ scale: Scale) -> String {
    switch scale {
    case .servings(let servings): Copy.recipeView.serves(servings).text
    case .multiplier(let factor):
      Copy.recipeView.scale(formatQuantity(Quantity(min: factor, max: nil), unit: nil)).text
    }
  }
}

enum RecipeSource {
  /// The link's host without "www.", or the text as it was when it isn't a link.
  static func host(_ url: String) -> String {
    SiteName.of(url) ?? url
  }

  /// The link, when it is one a browser should open.
  static func link(_ url: String) -> URL? {
    guard let link = URL(string: url), ["http", "https"].contains(link.scheme?.lowercased()),
      link.host() != nil
    else { return nil }
    return link
  }
}

enum RecipeDates {
  /// "Oct 1", in the cook's calendar.
  static func short(_ day: LocalDate, locale: Locale = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    guard
      let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
    else { return day.description }
    return date.formatted(
      Date.FormatStyle(calendar: calendar).locale(locale).month(.abbreviated).day())
  }
}
