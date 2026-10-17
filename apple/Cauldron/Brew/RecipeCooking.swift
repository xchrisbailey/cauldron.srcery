import CauldronKit
import Foundation
import SwiftData

/// Marking a recipe cooked, as the web's "Brewed" does: one entry for each day it was cooked
/// (cooking it twice on a day is one), and the recipe remembers the latest day.
enum RecipeCooking {
  static func markCooked(
    _ recipe: RecipeRecord, on day: LocalDate, context: ModelContext, now: Date = .now
  ) throws {
    let key = day.description
    if !(recipe.cooks ?? []).contains(where: { $0.cookedOnKey == key }) {
      let cook = CookRecord(cookedOn: day)
      context.insert(cook)
      cook.recipe = recipe
    }
    if let last = recipe.lastCookedOn, last >= day {
      // An earlier day never moves "last cooked" back.
    } else {
      recipe.lastCookedOn = day
    }
    recipe.updatedAt = now
    try context.save()
  }

  /// Today in the cook's own calendar.
  static func today(now: Date = .now, calendar: Calendar = .current) -> LocalDate? {
    let parts = calendar.dateComponents([.year, .month, .day], from: now)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    return LocalDate(year: year, month: month, day: day)
  }
}
