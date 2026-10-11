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
    /// Rows left out because their day isn't a real day. The app never writes one, so this
    /// is a store damaged some other way, and the export says so rather than hiding it.
    var skipped: Int
  }

  static func document(
    from context: ModelContext, exportedAt: Date, appVersion: String?
  ) throws -> Mapped {
    var skipped = 0
    /// Maps rows that carry a day, counting the ones whose day can't be read.
    func withDays<Row, Out>(_ rows: [Row], _ map: (Row) -> Out?) -> [Out] {
      let mapped = rows.compactMap(map)
      skipped += rows.count - mapped.count
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
      .map { recipe(from: $0, winnerOfTag: winnerOfTag) }
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
    document.cooks = withDays(cooks.sorted(by: created)) { cook in
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
    document.planEntries = withDays(plan) { entry in
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
    document.gatherItems = withDays(gather) { item in
      item.weekStart.map {
        ExportedGatherItem(
          id: item.id, weekStart: $0, item: item.item, itemKey: item.itemKey,
          quantity: quantity(item.quantityMin, item.quantityMax), unit: item.unitRaw,
          aisle: item.aisleRaw, checked: item.checked, manual: item.manual,
          position: item.position,
          sources: (item.sources ?? []).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            ExportedGatherSource(
              id: $0.id, recipeId: $0.recipe?.id,
              quantity: quantity($0.quantityMin, $0.quantityMax), unit: $0.unitRaw)
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
    document.diary = withDays(diary) { entry in
      entry.day.map {
        ExportedDiaryEntry(
          id: entry.id, day: $0, slot: entry.slotRaw, name: entry.name, amount: entry.amount,
          servings: entry.servings,
          macros: macros(entry.calories, entry.protein, entry.carbs, entry.fat),
          source: entry.sourceRaw, position: entry.position,
          macrosPending: entry.macrosPending, recipeId: entry.recipe?.id,
          createdAt: ms(entry.createdAt), updatedAt: ms(entry.updatedAt))
      }
    }

    document.favourites = Deduplication.winners(
      of: try context.fetch(FetchDescriptor<FavouriteRecord>()), key: { $0.key }
    ).sorted(by: created).map {
      ExportedFavourite(
        id: $0.id, key: $0.key, name: $0.name, amount: $0.amount, servings: $0.servings,
        macros: macros($0.calories, $0.protein, $0.carbs, $0.fat), source: $0.sourceRaw,
        recipeId: $0.recipe?.id, createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt))
    }

    let weighIns = Deduplication.winners(
      of: try context.fetch(FetchDescriptor<WeighInRecord>()), key: { $0.dayKey }
    ).sorted { ($0.dayKey, $0.id.uuidString) < ($1.dayKey, $1.id.uuidString) }
    document.weighIns = withDays(weighIns) { weighIn in
      weighIn.day.map {
        ExportedWeighIn(
          id: weighIn.id, day: $0, weightKg: weighIn.weightKg,
          healthSampleID: weighIn.healthSampleID, createdAt: ms(weighIn.createdAt),
          updatedAt: ms(weighIn.updatedAt))
      }
    }

    document.bodyProfile = try context.current(BodyProfileRecord.self).map {
      ExportedBodyProfile(
        id: $0.id, sex: $0.sexRaw, birthDate: $0.birthDate, heightCm: $0.heightCm,
        activity: $0.activityRaw, goal: $0.goalRaw, weeklyRateKg: $0.weeklyRateKg,
        proteinPerKg: $0.proteinPerKg, fatShare: $0.fatShare, weightUnit: $0.weightUnitRaw,
        heightUnit: $0.heightUnitRaw, createdAt: ms($0.createdAt), updatedAt: ms($0.updatedAt))
    }
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
    return Mapped(document: document, skipped: skipped)
  }

  // MARK: Pieces

  private static func recipe(
    from recipe: RecipeRecord, winnerOfTag: [UUID: UUID]
  ) -> ExportedRecipe {
    // Read from the stored JSON as the export's own types, not through `recipe.ingredients`,
    // which only knows the units this build has. A line from a newer build keeps its unit.
    var tagIds: [UUID] = []
    for tag in recipe.tags ?? [] {
      let id = winnerOfTag[tag.id] ?? tag.id
      if !tagIds.contains(id) { tagIds.append(id) }
    }
    return ExportedRecipe(
      id: recipe.id, title: recipe.title, summary: recipe.summary, notes: recipe.notes,
      servings: recipe.servings, prepMinutes: recipe.prepMinutes, cookMinutes: recipe.cookMinutes,
      totalMinutes: recipe.totalMinutes,
      source: ExportedSource(
        platform: recipe.sourcePlatformRaw, url: recipe.sourceURL, author: recipe.sourceAuthor,
        fetchedAt: recipe.sourceFetchedAt.map(ms)),
      macros: macros(recipe.calories, recipe.protein, recipe.carbs, recipe.fat),
      macrosSource: recipe.macrosSourceRaw, macrosPending: recipe.macrosPending,
      ingredients: StoredJSON.decodeList(ExportedIngredient.self, from: recipe.ingredientsData)
        .values,
      steps: StoredJSON.decodeList(ExportedStep.self, from: recipe.stepsData).values,
      tagIds: tagIds, lastCookedOn: recipe.lastCookedOn, deletedAt: recipe.deletedAt.map(ms),
      createdAt: ms(recipe.createdAt), updatedAt: ms(recipe.updatedAt))
  }

  private static func ms(_ date: Date) -> Date { ExportCoding.milliseconds(date) }

  private static func quantity(_ min: Double?, _ max: Double?) -> ExportedQuantity? {
    min.map { ExportedQuantity(min: $0, max: max) }
  }

  private static func macros(
    _ calories: Double?, _ protein: Double?, _ carbs: Double?, _ fat: Double?
  ) -> ExportedMacros {
    ExportedMacros(calories: calories, protein: protein, carbs: carbs, fat: fat)
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
