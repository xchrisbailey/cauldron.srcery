import CauldronKit
import Foundation
import SwiftData

/// Duplicating a recipe, as the web's `POST /recipes/:id/duplicate` does: the copy takes
/// everything the cook wrote (title as "<title> (copy)", the summary, servings and times, the
/// source, notes, photo, ingredients, steps, tags and macros) and none of its history: it was
/// never cooked, and it is not on the week, Gather or the diary.
enum RecipeDuplication {
  /// Makes the copy and saves it. The original is not touched.
  @discardableResult
  static func duplicate(
    _ recipe: RecipeRecord, context: ModelContext, now: Date = .now
  ) throws -> RecipeRecord {
    let copy = RecipeRecord(
      title: String(Copy.recipes.copyOf(recipe.title).text.prefix(RecipeLimits.title)))
    context.insert(copy)
    copy.summary = recipe.summary
    copy.notes = recipe.notes
    copy.servings = recipe.servings
    copy.prepMinutes = recipe.prepMinutes
    copy.cookMinutes = recipe.cookMinutes
    copy.totalMinutes = recipe.totalMinutes
    copy.sourcePlatformRaw = recipe.sourcePlatformRaw
    copy.sourceURL = recipe.sourceURL
    copy.sourceAuthor = recipe.sourceAuthor
    copy.sourceFetchedAt = recipe.sourceFetchedAt
    // The stored JSON as it is, so a line this build can't read isn't lost from the copy.
    copy.ingredientsData = recipe.ingredientsData
    copy.stepsData = recipe.stepsData
    copy.macros = recipe.macros
    copy.macrosSourceRaw = recipe.macrosSourceRaw
    // A queued estimate belongs to the original's job, so the copy isn't left waiting on one.
    copy.macrosPending = false
    if let photo = recipe.photo, let data = photo.imageData {
      let photoCopy = PhotoRecord(imageData: data, width: photo.width, height: photo.height)
      context.insert(photoCopy)
      photoCopy.recipe = copy
    }
    copy.tags = recipe.tags
    copy.refreshSearchText()
    copy.createdAt = now
    copy.updatedAt = now
    try context.save()
    return copy
  }
}
