import CauldronImports
import CauldronKit
import Foundation
import SwiftData

/// Writes a `RecipeDraft` to a recipe: a new one, or the one being edited. Nothing is changed
/// unless the whole draft is valid.
enum RecipeSaver {
  enum Failure: Error {
    /// The draft has problems; what to show, by field.
    case invalid(RecipeDraft.Errors)
  }

  /// Saves `draft` into `recipe`, or into a new recipe when it's nil, and saves the context.
  /// Throws `Failure.invalid` for a draft that fails validation, before anything is touched.
  /// A new recipe gets `id` when it is given: the share sheet's finished recipes bring their
  /// own, so receiving one twice can tell it is there. Once the recipe is saved the saved-links
  /// index is rewritten, so the share sheet knows its link.
  @discardableResult
  static func save(
    _ draft: RecipeDraft, into existing: RecipeRecord?, context: ModelContext, now: Date = .now,
    id: UUID? = nil, index: SavedLinksIndex = .live
  ) throws -> RecipeRecord {
    let errors = draft.validate()
    guard errors.isEmpty else { throw Failure.invalid(errors) }

    let recipe = existing ?? RecipeRecord(title: "")
    if existing == nil {
      if let id { recipe.id = id }
      context.insert(recipe)
    }
    // Where an import came from is recorded once, when it becomes a recipe.
    if existing == nil, let imported = draft.imported {
      recipe.sourcePlatform = imported.platform
      recipe.sourceAuthor = imported.author.flatMap { $0.isEmpty ? nil : $0 }
      recipe.sourceFetchedAt = imported.fetchedAt
    }

    recipe.title = draft.trimmed(draft.title)
    recipe.summary = optional(draft.summary, draft)
    recipe.notes = optional(draft.notes, draft)
    recipe.sourceURL = optional(draft.sourceURL, draft)
    recipe.servings = RecipeDraft.whole(draft.servings, in: 1...RecipeLimits.servings).number
    recipe.prepMinutes = RecipeDraft.whole(draft.prepMinutes, in: 0...RecipeLimits.minutes).number
    recipe.cookMinutes = RecipeDraft.whole(draft.cookMinutes, in: 0...RecipeLimits.minutes).number
    recipe.totalMinutes = RecipeDraft.whole(draft.totalMinutes, in: 0...RecipeLimits.minutes).number
    saveMacros(draft, into: recipe)

    if !draft.ingredientsLocked { recipe.ingredients = ingredients(of: draft) }
    if !draft.stepsLocked { recipe.steps = steps(of: draft) }
    saveTags(draft, into: recipe, context: context)
    savePhoto(draft.photo, into: recipe, context: context)

    recipe.refreshSearchText()
    recipe.updatedAt = now
    try context.save()
    index.rewrite(from: context)
    return recipe
  }

  private static func optional(_ text: String, _ draft: RecipeDraft) -> String? {
    let trimmed = draft.trimmed(text)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Macros the cook typed are manual, ones the model estimated into the fields (and the cook
  /// left alone) are an estimate, and ones an imported page published are the page's. Ones they
  /// didn't touch keep how they were worked out, and cleared ones have no source.
  private static func saveMacros(_ draft: RecipeDraft, into recipe: RecipeRecord) {
    let typed = draft.typedMacros
    if typed != recipe.macros {
      recipe.macros = typed
      recipe.macrosSource = source(of: typed, in: draft)
    }
  }

  private static func source(of typed: Macros, in draft: RecipeDraft) -> MacrosSource? {
    if typed == Macros() { return nil }
    if typed == draft.estimatedMacros { return .estimated }
    if typed == draft.pageMacros { return .page }
    return .manual
  }

  /// The lines with the heading above each as its `section`; blank lines are left out.
  private static func ingredients(of draft: RecipeDraft) -> [Ingredient] {
    var section: String?
    var lines: [Ingredient] = []
    for row in draft.ingredients {
      if row.isHeading {
        let heading = draft.trimmed(row.text)
        section = heading.isEmpty ? nil : heading
        continue
      }
      guard !row.isBlank, let parsed = row.parsed else { continue }
      lines.append(
        Ingredient(
          section: section, quantity: parsed.quantity, unit: parsed.unit,
          item: draft.trimmed(parsed.item), note: parsed.note, optional: parsed.optional,
          alt: parsed.alt, original: draft.trimmed(row.text), itemKey: ingredientKey(parsed.item)))
    }
    return lines
  }

  private static func steps(of draft: RecipeDraft) -> [Step] {
    draft.steps.filter { !$0.isBlank }.map {
      Step(section: $0.section, text: draft.trimmed($0.text), timerSeconds: $0.timerSeconds)
    }
  }

  /// Reuses a tag with the same name in any case, and only makes one when there isn't one.
  private static func saveTags(
    _ draft: RecipeDraft, into recipe: RecipeRecord, context: ModelContext
  ) {
    let all = (try? context.fetch(FetchDescriptor<TagRecord>())) ?? []
    var byName: [String: [TagRecord]] = [:]
    for tag in all { byName[tag.name.lowercased(), default: []].append(tag) }
    var chosen: [TagRecord] = []
    for name in draft.tags.map(draft.trimmed) where !name.isEmpty {
      let key = name.lowercased()
      if chosen.contains(where: { $0.name.lowercased() == key }) { continue }
      if let tag = Deduplication.keeper(of: byName[key] ?? []) {
        chosen.append(tag)
      } else {
        let tag = TagRecord(name: name)
        context.insert(tag)
        byName[key] = [tag]
        chosen.append(tag)
      }
    }
    recipe.tags = chosen
  }

  private static func savePhoto(
    _ change: PhotoChange, into recipe: RecipeRecord, context: ModelContext
  ) {
    switch change {
    case .keep:
      break
    case .remove:
      if let photo = recipe.photo { context.delete(photo) }
      recipe.photo = nil
    case .replace(let processed):
      let photo = recipe.photo ?? PhotoRecord(imageData: nil, width: 0, height: 0)
      photo.imageData = processed.data
      photo.width = processed.width
      photo.height = processed.height
      if recipe.photo == nil {
        context.insert(photo)
        recipe.photo = photo
      }
    }
  }
}
