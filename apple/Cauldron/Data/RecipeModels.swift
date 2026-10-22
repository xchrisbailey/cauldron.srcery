import CauldronKit
import Foundation
import SwiftData

// Every model here follows the CloudKit rules in docs/native/data-model.md: each property is
// optional or has a default, each relationship is optional and has an inverse, and nothing is
// unique. Enums and days are stored as their raw strings, with typed accessors beside them.

/// A recipe. Ingredients and steps are stored structured, as the JSON of `[Ingredient]` and
/// `[Step]`, so a recipe syncs as one record and its lines can't arrive half-merged.
@Model
final class RecipeRecord {
  var id: UUID = UUID()
  var title: String = ""
  var summary: String?
  var notes: String?
  var servings: Int?
  var prepMinutes: Int?
  var cookMinutes: Int?
  var totalMinutes: Int?

  var sourcePlatformRaw: String = SourcePlatform.manual.rawValue
  var sourceURL: String?
  var sourceAuthor: String?
  var sourceFetchedAt: Date?

  var ingredientsData: Data = Data()
  var stepsData: Data = Data()
  /// Lowercased title, ingredient items and tag names, for search.
  var searchText: String = ""

  // Per serving. Any of them can be unknown.
  var calories: Double?
  var protein: Double?
  var carbs: Double?
  var fat: Double?
  var macrosSourceRaw: String?
  /// True while a macro estimate is queued for this recipe.
  var macrosPending: Bool = false

  var lastCookedOnKey: String?
  /// Set when the recipe is banished; it can be restored until it is purged.
  var deletedAt: Date?
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now

  /// An explicit photo removal also declines a deferred imported cover.
  var coverDeclined: Bool = false

  @Relationship(deleteRule: .cascade, inverse: \PhotoRecord.recipe)
  var photo: PhotoRecord?
  @Relationship(inverse: \TagRecord.recipes)
  var tags: [TagRecord]? = []
  @Relationship(deleteRule: .cascade, inverse: \CookRecord.recipe)
  var cooks: [CookRecord]? = []
  @Relationship(deleteRule: .nullify, inverse: \PlanEntryRecord.recipe)
  var planEntries: [PlanEntryRecord]? = []
  @Relationship(deleteRule: .nullify, inverse: \PlannedBatchRecord.recipe)
  var plannedBatches: [PlannedBatchRecord]? = []
  @Relationship(deleteRule: .cascade, inverse: \GatherSourceRecord.recipe)
  var gatherSources: [GatherSourceRecord]? = []
  @Relationship(deleteRule: .nullify, inverse: \DiaryEntryRecord.recipe)
  var diaryEntries: [DiaryEntryRecord]? = []
  @Relationship(deleteRule: .nullify, inverse: \FavouriteRecord.recipe)
  var favourites: [FavouriteRecord]? = []
  @Relationship(deleteRule: .cascade, inverse: \AIJobRecord.recipe)
  var aiJobs: [AIJobRecord]? = []

  init(title: String) {
    self.title = title
  }

  /// The lines this build can read. A line it can't (written by a newer build) is left out
  /// here but stays in `ingredientsData`; see `canRewriteIngredients`.
  var ingredients: [Ingredient] {
    get { StoredJSON.decodeList(Ingredient.self, from: ingredientsData).values }
    set { StoredJSON.store(newValue, in: &ingredientsData) }
  }

  var steps: [Step] {
    get { StoredJSON.decodeList(Step.self, from: stepsData).values }
    set { StoredJSON.store(newValue, in: &stepsData) }
  }

  /// False when the stored lines hold something this build can't read. Saving `ingredients`
  /// then would drop it for every device, so an editor must not offer to.
  var canRewriteIngredients: Bool {
    StoredJSON.decodeList(Ingredient.self, from: ingredientsData).complete
  }

  var canRewriteSteps: Bool {
    StoredJSON.decodeList(Step.self, from: stepsData).complete
  }

  /// Rebuilds `searchText` from the title, ingredient items and tag names. Call it after
  /// changing any of them.
  func refreshSearchText() {
    let words = [title] + ingredients.map(\.item) + (tags ?? []).map(\.name)
    searchText = words.joined(separator: " ").lowercased()
  }

  var sourcePlatform: SourcePlatform {
    get { SourcePlatform(rawValue: sourcePlatformRaw) ?? .manual }
    set { sourcePlatformRaw = newValue.rawValue }
  }

  var macros: Macros {
    get { Macros(calories: calories, protein: protein, carbs: carbs, fat: fat) }
    set {
      calories = newValue.calories
      protein = newValue.protein
      carbs = newValue.carbs
      fat = newValue.fat
    }
  }

  var macrosSource: MacrosSource? {
    get { macrosSourceRaw.flatMap(MacrosSource.init(rawValue:)) }
    set { macrosSourceRaw = newValue?.rawValue }
  }

  var lastCookedOn: LocalDate? {
    get { lastCookedOnKey.flatMap { LocalDate($0) } }
    set { lastCookedOnKey = newValue?.description }
  }

  var isBanished: Bool { deletedAt != nil }
}

/// Where a recipe's macros came from.
enum MacrosSource: String, CaseIterable, Sendable {
  /// Typed in by hand.
  case manual
  /// Read from the nutrition data on the imported page.
  case page
  /// Estimated from the ingredients by the model.
  case estimated
}

/// A recipe's photo. The image lives outside the database file.
@Model
final class PhotoRecord {
  var id: UUID = UUID()
  @Attribute(.externalStorage) var imageData: Data?
  var width: Int = 0
  var height: Int = 0
  var createdAt: Date = Date.now
  var recipe: RecipeRecord?

  init(imageData: Data?, width: Int, height: Int) {
    self.imageData = imageData
    self.width = width
    self.height = height
  }
}

@Model
final class TagRecord {
  var id: UUID = UUID()
  var name: String = ""
  var kindRaw: String = TagKind.other.rawValue
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now
  var recipes: [RecipeRecord]? = []

  init(name: String, kind: TagKind = .other) {
    self.name = name
    self.kindRaw = kind.rawValue
  }

  var kind: TagKind {
    get { TagKind(rawValue: kindRaw) ?? .other }
    set { kindRaw = newValue.rawValue }
  }
}

/// One day a recipe was cooked.
@Model
final class CookRecord {
  var id: UUID = UUID()
  var cookedOnKey: String = ""
  var createdAt: Date = Date.now
  var recipe: RecipeRecord?

  init(cookedOn: LocalDate) {
    self.cookedOnKey = cookedOn.description
  }

  var cookedOn: LocalDate? { LocalDate(cookedOnKey) }
}

/// An entry on the week plan: a recipe, or a free-text meal when `recipe` is nil.
@Model
final class PlanEntryRecord {
  var id: UUID = UUID()
  var dayKey: String = ""
  var slotRaw: String = MealSlot.dinner.rawValue
  var title: String = ""
  var servings: Int?
  var position: Int = 0
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now
  var recipe: RecipeRecord?
  var batch: PlannedBatchRecord?

  init(day: LocalDate, slot: MealSlot, title: String, servings: Int? = nil, position: Int = 0) {
    self.dayKey = day.description
    self.slotRaw = slot.rawValue
    self.title = title
    self.servings = servings
    self.position = position
  }

  var day: LocalDate? {
    get { LocalDate(dayKey) }
    set { dayKey = newValue?.description ?? "" }
  }

  var slot: MealSlot {
    get { MealSlot(rawValue: slotRaw) ?? .dinner }
    set { slotRaw = newValue.rawValue }
  }
}

/// A planned quantity of a recipe in one immutable seven-day range.
@Model
final class PlannedBatchRecord {
  var id: UUID = UUID()
  var weekStartKey: String = ""
  var title: String = ""
  var totalServings: Int = 1
  var ingredientYield: Int = 1
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now
  var recipe: RecipeRecord?
  @Relationship(deleteRule: .cascade, inverse: \PlanEntryRecord.batch)
  var entries: [PlanEntryRecord]? = []

  init(weekStart: LocalDate, title: String, totalServings: Int, ingredientYield: Int) {
    weekStartKey = weekStart.description
    self.title = title
    self.totalServings = totalServings
    self.ingredientYield = ingredientYield
  }

  var weekStart: LocalDate? { LocalDate(weekStartKey) }
}

/// A line on the Gather list for one week.
@Model
final class GatherItemRecord {
  var id: UUID = UUID()
  var weekStartKey: String = ""
  var item: String = ""
  var itemKey: String = ""
  var quantityMin: Double?
  var quantityMax: Double?
  var unitRaw: String?
  var aisleRaw: String?
  var checked: Bool = false
  var manual: Bool = false
  var position: Int = 0
  var createdAt: Date = Date.now
  var updatedAt: Date = Date.now

  @Relationship(deleteRule: .cascade, inverse: \GatherSourceRecord.item)
  var sources: [GatherSourceRecord]? = []

  init(weekStart: LocalDate, item: String, itemKey: String) {
    self.weekStartKey = weekStart.description
    self.item = item
    self.itemKey = itemKey
  }

  var weekStart: LocalDate? { LocalDate(weekStartKey) }

  var quantity: Quantity? {
    get { quantityMin.map { Quantity(min: $0, max: quantityMax) } }
    set {
      quantityMin = newValue?.min
      quantityMax = newValue?.max
    }
  }

  var unit: UnitCode? {
    get { unitRaw.flatMap(UnitCode.init(rawValue:)) }
    set { unitRaw = newValue?.rawValue }
  }

  var aisle: Aisle? {
    get { aisleRaw.flatMap(Aisle.init(rawValue:)) }
    set { aisleRaw = newValue?.rawValue }
  }
}

/// How much of a Gather line one recipe asked for.
@Model
final class GatherSourceRecord {
  var id: UUID = UUID()
  var quantityMin: Double?
  var quantityMax: Double?
  var unitRaw: String?
  var item: GatherItemRecord?
  var recipe: RecipeRecord?

  init(quantity: Quantity?, unit: UnitCode?) {
    self.quantityMin = quantity?.min
    self.quantityMax = quantity?.max
    self.unitRaw = unit?.rawValue
  }

  var quantity: Quantity? { quantityMin.map { Quantity(min: $0, max: quantityMax) } }
  var unit: UnitCode? { unitRaw.flatMap(UnitCode.init(rawValue:)) }
}

/// Something already in the pantry, so Gather can leave it off the list.
@Model
final class PantryItemRecord {
  var id: UUID = UUID()
  var itemKey: String = ""
  var createdAt: Date = Date.now

  init(itemKey: String) {
    self.itemKey = itemKey
  }
}

/// Lists of value types stored as JSON in one column.
enum StoredJSON {
  /// Writes `values` into `data`. A list that can't be encoded (a quantity that isn't a
  /// finite number) leaves what was stored untouched, so a bad edit can't empty a recipe.
  static func store(_ values: [some Encodable], in data: inout Data) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let encoded = try? encoder.encode(values) else { return }
    data = encoded
  }

  /// Reads a list one element at a time, so an element this build can't read costs only
  /// itself. `complete` is false when anything was skipped.
  static func decodeList<Value: Decodable>(
    _ type: Value.Type, from data: Data
  ) -> (values: [Value], complete: Bool) {
    guard !data.isEmpty else { return ([], true) }
    guard let elements = try? JSONDecoder().decode([Lossy<Value>].self, from: data) else {
      return ([], false)
    }
    let values = elements.compactMap(\.value)
    return (values, values.count == elements.count)
  }

  private struct Lossy<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
      value = try? Value(from: decoder)
    }
  }
}
