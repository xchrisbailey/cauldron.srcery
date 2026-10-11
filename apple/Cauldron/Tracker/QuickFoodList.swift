import CauldronKit
import Foundation
import SwiftData

// Recents and favourites: what the add sheet offers to log again in one tap. Ported from
// `Tracker.quickFoods` in `apps/api/src/Tracker.ts` and `Recents.tsx`.

extension DiaryEntryRecord {
  /// The entry as a food that can be logged again, as it was last logged.
  var quickFood: QuickFood {
    QuickFood(
      name: name, amount: amount, servings: servings, macros: macros, source: source,
      recipeId: recipe?.id)
  }
}

extension FavouriteRecord {
  var food: QuickFood {
    QuickFood(
      name: name, amount: amount, servings: servings, macros: macros, source: source,
      recipeId: recipe?.id)
  }
}

enum QuickFoodList {
  /// Foods logged in this many days back are recents.
  static let recentDays = 60
  /// At most this many recents are offered.
  static let recentMax = 30

  /// Favourites by name, then what was logged lately: most often first, and the most recent
  /// among those as often, each as it was last logged. Foods that are starred are favourites,
  /// not recents. Entries still waiting for their numbers aren't offered (logging one again
  /// would copy nothing).
  static func foods(
    favourites: [FavouriteRecord], entries: [DiaryEntryRecord], today: LocalDate
  ) -> QuickFoods {
    let starred = favouriteList(favourites)
    let starredKeys = Set(starred.map { quickFoodKey($0.food) })

    let from = today.adding(days: -recentDays).description
    // Newest first, so the first of a food is how it was last logged.
    let recent = entries.filter { !$0.macrosPending && $0.dayKey >= from }.sorted {
      ($0.dayKey, $0.createdAt, $0.id.uuidString) > ($1.dayKey, $1.createdAt, $1.id.uuidString)
    }
    var order: [String] = []
    var groups: [String: RecentFood] = [:]
    for entry in recent {
      guard let day = entry.day else { continue }
      let food = entry.quickFood
      let key = quickFoodKey(food)
      if var group = groups[key] {
        group.count += 1
        groups[key] = group
      } else {
        order.append(key)
        groups[key] = RecentFood(food: food, count: 1, lastLoggedOn: day, lastEntryId: entry.id)
      }
    }
    let recents =
      order
      .filter { !starredKeys.contains($0) }
      .compactMap { groups[$0] }
      .sorted { ($0.count, $0.lastLoggedOn) > ($1.count, $1.lastLoggedOn) }
      .prefix(recentMax)
    return QuickFoods(favourites: starred, recents: Array(recents))
  }

  /// One favourite per food (the keeper rule picks among duplicates), by name.
  static func favouriteList(_ rows: [FavouriteRecord]) -> [Favourite] {
    Dictionary(grouping: rows, by: \.key).values.compactMap { Deduplication.keeper(of: $0) }
      .sorted {
        let (a, b) = ($0.name.lowercased(), $1.name.lowercased())
        return a != b ? a < b : $0.id.uuidString < $1.id.uuidString
      }
      .map { Favourite(id: $0.id, food: $0.food) }
  }

  /// Logging a food again: what it was, as it was last logged.
  @MainActor
  static func entry(for food: QuickFood, in context: ModelContext) -> NewEntry {
    NewEntry(
      name: food.name, amount: food.amount, servings: food.servings, macros: food.macros,
      source: food.source, recipe: recipe(food.recipeId, in: context))
  }

  /// The recipe an entry came from, while it still exists (banished counts: it is the cook's).
  @MainActor
  static func recipe(_ id: UUID?, in context: ModelContext) -> RecipeRecord? {
    guard let id else { return nil }
    return try? context.fetch(FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id }))
      .first
  }
}

/// Starring and unstarring. One favourite per food: starring one that exists changes it to how
/// the entry is now.
enum FavouriteWrites {
  enum Failure: Error {
    /// The entry has no numbers yet (a described meal waiting for them).
    case pending
  }

  static func key(of entry: DiaryEntryRecord) -> String {
    quickFoodKey(entry.quickFood)
  }

  @MainActor
  static func star(_ entry: DiaryEntryRecord, in context: ModelContext) throws {
    guard !entry.macrosPending else { throw Failure.pending }
    let food = entry.quickFood
    let key = quickFoodKey(food)
    let existing = try context.fetch(
      FetchDescriptor<FavouriteRecord>(predicate: #Predicate { $0.key == key }))
    let row =
      Deduplication.keeper(of: existing)
      ?? {
        let row = FavouriteRecord(key: key, name: food.name, source: food.source)
        context.insert(row)
        return row
      }()
    row.name = food.name
    row.amount = food.amount
    row.servings = food.servings
    row.macros = food.macros
    row.source = food.source
    row.recipe = entry.recipe
    try commit(context)
  }

  /// Takes the food off the favourites (every row for it, if two devices each made one).
  @MainActor
  static func unstar(key: String, in context: ModelContext) throws {
    let rows = try context.fetch(
      FetchDescriptor<FavouriteRecord>(predicate: #Predicate { $0.key == key }))
    for row in rows { context.delete(row) }
    try commit(context)
  }

  @MainActor
  private static func commit(_ context: ModelContext) throws {
    do {
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
}
