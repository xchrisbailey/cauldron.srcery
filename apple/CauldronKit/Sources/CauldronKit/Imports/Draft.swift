import Foundation

// Tidies what an extractor read into a draft the editor can open: trimmed, cut to the recipe
// limits, numbers in range, and flags where a cook should look before saving (`draft.ts`).

/// Where a draft came from.
public struct DraftSource: Sendable, Hashable {
  public var source: ImportSource
  public var sourceUrl: String?
  public var photoKey: String?

  public init(source: ImportSource, sourceUrl: String?, photoKey: String? = nil) {
    self.source = source
    self.sourceUrl = sourceUrl
    self.photoKey = photoKey
  }
}

extension ImportDraft {
  private static let lineBreaksInNotes = JSRegex("[ \\t]+")
  private static let manyBlankLines = JSRegex("\\n{3,}")
  private static let leadingHash = JSRegex("^#")

  private static func text(_ value: String?, _ max: Int) -> String? {
    let trimmed = (value ?? "").jsSpacesCollapsed().jsTrimmed()
    return trimmed.isEmpty ? nil : trimmed.jsPrefix(max)
  }

  /// Keeps line breaks, for notes.
  private static func block(_ value: String?, _ max: Int) -> String? {
    let trimmed = manyBlankLines.replacing(
      in: lineBreaksInNotes.replacing(in: value ?? "", with: " "), with: "\n\n"
    ).jsTrimmed()
    return trimmed.isEmpty ? nil : trimmed.jsPrefix(max)
  }

  private static func int(_ value: Int?, _ min: Int, _ max: Int) -> Int? {
    guard let value, value >= min, value <= max else { return nil }
    return value
  }

  private static func int(_ value: Double?, _ min: Int, _ max: Int) -> Double? {
    guard let value, value.isFinite, value >= Double(min), value <= Double(max) else { return nil }
    return jsRound(value)
  }

  /// Grams to one decimal place, the precision the recipe stores.
  private static func grams(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0, value <= Double(RecipeLimits.grams) else {
      return nil
    }
    return jsRound(value * 10) / 10
  }

  /// A draft from what an extractor read (`toDraft`).
  public init(reading recipe: ExtractedRecipe, from source: DraftSource) {
    var unsure = Set(recipe.unsure)
    let title = Self.text(recipe.title, RecipeLimits.title)
    if title == nil { unsure.insert(.title) }

    let ingredients = recipe.ingredients.prefix(RecipeLimits.ingredients).compactMap {
      ingredient -> DraftIngredient? in
      guard let line = Self.text(ingredient.line, RecipeLimits.line) else { return nil }
      // A line the parser reads with no item would fail the editor's check, so it's flagged
      // here as well.
      let parsed = parseIngredientLine(line)
      return DraftIngredient(
        line: line, section: Self.text(ingredient.section, RecipeLimits.section),
        unsure: ingredient.unsure || parsed.item.jsTrimmed().isEmpty)
    }

    let steps = recipe.steps.prefix(RecipeLimits.steps).compactMap { step -> DraftStep? in
      guard let text = Self.text(step.text, RecipeLimits.step) else { return nil }
      return DraftStep(
        text: text, section: Self.text(step.section, RecipeLimits.section), unsure: step.unsure)
    }

    var seen = Set<String>()
    var tags: [String] = []
    for tag in recipe.tags {
      guard
        let name = Self.text(Self.leadingHash.replacingFirst(in: tag, with: ""), RecipeLimits.tag)
      else { continue }
      if seen.insert(jsLowercased(name)).inserted { tags.append(name) }
    }

    self.init(
      title: title ?? "",
      description: Self.text(recipe.description, RecipeLimits.description),
      servings: Self.int(recipe.servings, 1, RecipeLimits.servings),
      prepMinutes: Self.int(recipe.prepMinutes, 0, RecipeLimits.minutes),
      cookMinutes: Self.int(recipe.cookMinutes, 0, RecipeLimits.minutes),
      totalMinutes: Self.int(recipe.totalMinutes, 0, RecipeLimits.minutes),
      macros: recipe.macros.map {
        Macros(
          calories: Self.int($0.calories, 0, RecipeLimits.calories),
          protein: Self.grams($0.protein), carbs: Self.grams($0.carbs), fat: Self.grams($0.fat))
      },
      sourcePlatform: source.source,
      sourceUrl: source.sourceUrl?.jsPrefix(RecipeLimits.url),
      sourceAuthor: Self.text(recipe.author, RecipeLimits.author),
      siteName: Self.text(recipe.siteName, RecipeLimits.author),
      notes: Self.block(recipe.notes, RecipeLimits.notes),
      photoKey: source.photoKey,
      tags: Array(tags.prefix(RecipeLimits.tags)),
      ingredients: Array(ingredients),
      steps: Array(steps),
      unsure: DraftField.allCases.filter { unsure.contains($0) })
  }
}
