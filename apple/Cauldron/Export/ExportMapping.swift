import CauldronKit
import Foundation
import SwiftData

/// Turns what the store holds into the export format. Reads only; nothing is saved.
///
/// Where duplicates exist the winning row is the one exported, by the same rule the app reads
/// with (`Deduplication.keeper`), so an export shows what the cook sees. Photos are listed
/// without a `file`: the exporter fills that in as it writes each image.
enum ExportMapping {
  struct Mapped {
    var document: CauldronExport
    /// Rows and values left out because they can't be written: a day that isn't a real day,
    /// a number that isn't finite, or an ingredient or step list that can't be read. The app
    /// never writes one, so each is a store damaged some other way, and the export says so
    /// rather than hiding it.
    var skipped: Int
  }

  /// Counts what the export had to leave out.
  private final class Tally {
    var skipped = 0
  }

  static func document(
    from context: ModelContext, exportedAt: Date, appVersion: String?
  ) throws -> Mapped {
    let tally = Tally()
    /// Maps rows that can be written, counting the ones that can't: a day that can't be read,
    /// or a number the row can't do without that isn't finite.
    func keeping<Row, Out>(_ rows: [Row], _ map: (Row) -> Out?) -> [Out] {
      let mapped = rows.compactMap(map)
      tally.skipped += rows.count - mapped.count
      return mapped
    }
    // A recipe can point at either copy of a duplicate tag; the file names the winner.
    let allTags = try context.fetch(FetchDescriptor<TagRecord>())
    let tags = Deduplication.winners(of: allTags) { $0.name.lowercased() }
    let winnerByName = Dictionary(
      tags.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { first, _ in first })
    let winnerOfTag = Dictionary(
      allTags.compactMap { tag in winnerByName[tag.name.lowercased()].map { (tag.id, $0) } },
      uniquingKeysWith: { first, _ in first })

    var document = CauldronExport(
      exportedAt: ms(exportedAt), app: ExportedApp(name: "Cauldron", version: appVersion))

    document.recipes = try context.fetch(FetchDescriptor<RecipeRecord>())
      .sorted(by: created)
      .map { recipe(from: $0, winnerOfTag: winnerOfTag, tally: tally) }
    document.photos = try context.fetch(FetchDescriptor<PhotoRecord>())
      .sorted(by: created)
      .map {
        ExportedPhoto(
          id: $0.id, recipeId: $0.recipe?.id, file: nil, width: $0.width, height: $0.height,
          createdAt: ms($0.createdAt))
      }
    document.tags = tags.sorted(by: created).map {
      ExportedTag(
        id: $0.id, name: $0.name, kind: $0.kindRaw, createdAt: ms($0.createdAt),
        updatedAt: ms($0.updatedAt))
    }

    let cooks = Deduplication.winners(of: try context.fetch(FetchDescriptor<CookRecord>())) {
      cook in cook.recipe.map { "\($0.id.uuidString)|\(cook.cookedOnKey)" }
    }
    document.cooks = keeping(cooks.sorted(by: created)) { cook in
      cook.cookedOn.map {
        ExportedCook(
          id: cook.id, recipeId: cook.recipe?.id, cookedOn: $0, createdAt: ms(cook.createdAt))
      }
    }

    let plan = try context.fetch(FetchDescriptor<PlanEntryRecord>())
      .sorted {
        ($0.dayKey, slotOrder($0.slotRaw), $0.position, $0.id.uuidString) < (
          $1.dayKey, slotOrder($1.slotRaw), $1.position, $1.id.uuidString
        )
      }
    document.planEntries = keeping(plan) { entry in
      entry.day.map {
        ExportedPlanEntry(
          id: entry.id, day: $0, slot: entry.slotRaw, title: entry.title,
          servings: entry.servings, position: entry.position, recipeId: entry.recipe?.id,
          createdAt: ms(entry.createdAt), updatedAt: ms(entry.updatedAt))
      }
    }

    let gather = try context.fetch(FetchDescriptor<GatherItemRecord>())
      .sorted {
        ($0.weekStartKey, $0.position, $0.id.uuidString) < (
          $1.weekStartKey, $1.position, $1.id.uuidString
        )
      }
    document.gatherItems = keeping(gather) { item in
      item.weekStart.map {
        ExportedGatherItem(
          id: item.id, weekStart: $0, item: item.item, itemKey: item.itemKey,
          quantity: quantity(item.quantityMin, item.quantityMax, tally), unit: item.unitRaw,
          aisle: item.aisleRaw, checked: item.checked, manual: item.manual,
          position: item.position,
          sources: (item.sources ?? []).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            ExportedGatherSource(
              id: $0.id, recipeId: $0.recipe?.id,
              quantity: quantity($0.quantityMin, $0.quantityMax, tally), unit: $0.unitRaw)
          },
          createdAt: ms(item.createdAt), updatedAt: ms(item.updatedAt))
      }
    }

    document.pantry = Deduplication.winners(
      of: try context.fetch(FetchDescriptor<PantryItemRecord>()), key: { $0.itemKey }
    ).sorted(by: created).map {
      ExportedPantryItem(id: $0.id, itemKey: $0.itemKey, createdAt: ms($0.createdAt))
    }

    let diary = try context.fetch(FetchDescriptor<DiaryEntryRecord>())
      .sorted {
        ($0.dayKey, slotOrder($0.slotRaw), $0.position, $0.id.uuidString) < (
          $1.dayKey, slotOrder($1.slotRaw), $1.position, $1.id.uuidString
        )
      }
    document.diary = keeping(diary) { entry -> ExportedDiaryEntry? in
      // A meal with no servings figure isn't a meal worth keeping half of.
      guard let day = entry.day, entry.servings.isFinite else { return nil }
      return ExportedDiaryEntry(
        id: entry.id, day: day, slot: entry.slotRaw, name: entry.name, amount: entry.amount,
        servings: entry.servings,
        macros: macros(entry.calories, entry.protein, entry.carbs, entry.fat, tally),
        source: entry.sourceRaw, position: entry.position, macrosPending: entry.macrosPending,
        recipeId: entry.recipe?.id, createdAt: ms(entry.createdAt),
        updatedAt: ms(entry.updatedAt))
    }

    let favourites = Deduplication.winners(
      of: try context.fetch(FetchDescriptor<FavouriteRecord>()), key: { $0.key }
    ).sorted(by: created)
    document.favourites = keeping(favourites) { favourite -> ExportedFavourite? in
      guard favourite.servings.isFinite else { return nil }
      return ExportedFavourite(
        id: favourite.id, key: favourite.key, name: favourite.name, amount: favourite.amount,
        servings: favourite.servings,
        macros: macros(
          favourite.calories, favourite.protein, favourite.carbs, favourite.fat, tally),
        source: favourite.sourceRaw, recipeId: favourite.recipe?.id,
        createdAt: ms(favourite.createdAt), updatedAt: ms(favourite.updatedAt))
    }

    let weighIns = Deduplication.winners(
      of: try context.fetch(FetchDescriptor<WeighInRecord>()), key: { $0.dayKey }
    ).sorted { ($0.dayKey, $0.id.uuidString) < ($1.dayKey, $1.id.uuidString) }
    // A weigh-in is its number: without a finite one the row has nothing to keep.
    document.weighIns = keeping(weighIns) { weighIn -> ExportedWeighIn? in
      guard let day = weighIn.day, weighIn.weightKg.isFinite else { return nil }
      return ExportedWeighIn(
        id: weighIn.id, day: day, weightKg: weighIn.weightKg,
        healthSampleID: weighIn.healthSampleID, createdAt: ms(weighIn.createdAt),
        updatedAt: ms(weighIn.updatedAt))
    }

    // The profile's three rates are what the calculator runs on; without all of them finite
    // it is left out whole. The height is optional and is left out on its own.
    document.bodyProfile =
      keeping(try context.current(BodyProfileRecord.self).map { [$0] } ?? []) {
        profile -> ExportedBodyProfile? in
        guard profile.weeklyRateKg.isFinite, profile.proteinPerKg.isFinite,
          profile.fatShare.isFinite
        else { return nil }
        return ExportedBodyProfile(
          id: profile.id, sex: profile.sexRaw, birthDate: profile.birthDate,
          heightCm: finite(profile.heightCm, tally), activity: profile.activityRaw,
          goal: profile.goalRaw, weeklyRateKg: profile.weeklyRateKg,
          proteinPerKg: profile.proteinPerKg, fatShare: profile.fatShare,
          weightUnit: profile.weightUnitRaw, heightUnit: profile.heightUnitRaw,
          createdAt: ms(profile.createdAt), updatedAt: ms(profile.updatedAt))
      }.first
    document.targets = try context.current(TargetsRecord.self).map {
      ExportedTargets(
        id: $0.id, calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat,
        overridden: ExportedTargetOverrides(
          calories: $0.caloriesOverridden, protein: $0.proteinOverridden,
          carbs: $0.carbsOverridden, fat: $0.fatOverridden),
        checkedInOn: $0.checkedInOn, createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt))
    }
    document.preferences = try context.current(PreferencesRecord.self).map {
      ExportedPreferences(
        id: $0.id, weekStartsOn: $0.weekStartsOnRaw, unitSystem: $0.unitSystemRaw,
        createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt))
    }
    return Mapped(document: document, skipped: tally.skipped)
  }

  // MARK: Pieces

  private static func recipe(
    from recipe: RecipeRecord, winnerOfTag: [UUID: UUID], tally: Tally
  ) -> ExportedRecipe {
    // Read from the stored JSON as the export's own types, not through `recipe.ingredients`,
    // which only knows the units this build has. A line from a newer build keeps its unit.
    var tagIds: [UUID] = []
    for tag in recipe.tags ?? [] {
      let id = winnerOfTag[tag.id] ?? tag.id
      if !tagIds.contains(id) { tagIds.append(id) }
    }
    let ingredients = StoredJSON.decodeList(ExportedIngredient.self, from: recipe.ingredientsData)
    let steps = StoredJSON.decodeList(ExportedStep.self, from: recipe.stepsData)
    // A list with a line (or all of it) that can't be read is exported as far as it reads.
    if !ingredients.complete { tally.skipped += 1 }
    if !steps.complete { tally.skipped += 1 }
    return ExportedRecipe(
      id: recipe.id, title: recipe.title, summary: recipe.summary, notes: recipe.notes,
      servings: recipe.servings, prepMinutes: recipe.prepMinutes, cookMinutes: recipe.cookMinutes,
      totalMinutes: recipe.totalMinutes,
      source: ExportedSource(
        platform: recipe.sourcePlatformRaw, url: recipe.sourceURL, author: recipe.sourceAuthor,
        fetchedAt: recipe.sourceFetchedAt.map(ms)),
      macros: macros(recipe.calories, recipe.protein, recipe.carbs, recipe.fat, tally),
      macrosSource: recipe.macrosSourceRaw, macrosPending: recipe.macrosPending,
      ingredients: ingredients.values, steps: steps.values,
      tagIds: tagIds, lastCookedOn: recipe.lastCookedOn, deletedAt: recipe.deletedAt.map(ms),
      createdAt: ms(recipe.createdAt), updatedAt: ms(recipe.updatedAt))
  }

  private static func ms(_ date: Date) -> Date { ExportCoding.milliseconds(date) }

  /// A number the file can hold: JSON has no NaN or infinity, and one in the store would fail
  /// the whole export. It is left out, and counted.
  private static func finite(_ value: Double?, _ tally: Tally) -> Double? {
    guard let value else { return nil }
    guard value.isFinite else {
      tally.skipped += 1
      return nil
    }
    return value
  }

  private static func quantity(_ min: Double?, _ max: Double?, _ tally: Tally) -> ExportedQuantity?
  {
    guard let min = finite(min, tally) else { return nil }
    return ExportedQuantity(min: min, max: finite(max, tally))
  }

  private static func macros(
    _ calories: Double?, _ protein: Double?, _ carbs: Double?, _ fat: Double?, _ tally: Tally
  ) -> ExportedMacros {
    ExportedMacros(
      calories: finite(calories, tally), protein: finite(protein, tally),
      carbs: finite(carbs, tally), fat: finite(fat, tally))
  }

  private static func slotOrder(_ raw: String) -> Int {
    MealSlot.allCases.firstIndex { $0.rawValue == raw } ?? MealSlot.allCases.count
  }

  private static func created<Row: HasCreatedAt>(_ a: Row, _ b: Row) -> Bool {
    (a.createdAt, a.id.uuidString) < (b.createdAt, b.id.uuidString)
  }
}

/// Rows that can be put in the order they were made.
private protocol HasCreatedAt {
  var id: UUID { get }
  var createdAt: Date { get }
}

extension RecipeRecord: HasCreatedAt {}
extension PhotoRecord: HasCreatedAt {}
extension TagRecord: HasCreatedAt {}
extension CookRecord: HasCreatedAt {}
extension PantryItemRecord: HasCreatedAt {}
extension FavouriteRecord: HasCreatedAt {}

extension Deduplication {
  /// The rows the app would show: one per `key`, chosen by `keeper(of:)`. A row whose key is
  /// nil stands alone, as it does in `tidy`.
  static func winners<Row: Deduplicated>(of rows: [Row], key: (Row) -> String?) -> [Row] {
    var groups: [String: [Row]] = [:]
    var alone: [Row] = []
    for row in rows {
      if let key = key(row) { groups[key, default: []].append(row) } else { alone.append(row) }
    }
    return alone + groups.values.compactMap { keeper(of: $0) }
  }
}
