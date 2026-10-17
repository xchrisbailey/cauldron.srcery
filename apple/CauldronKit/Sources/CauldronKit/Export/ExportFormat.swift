import Foundation

// The export file, version 1. These types are the format: they are separate from the SwiftData
// models on purpose, so the schema can grow without a shipped format changing under it. A
// change to anything here changes what people have saved, so it follows the rules in
// docs/native/export-format.md, and `ExportFormatTests` pins the JSON.
//
// Rules the types keep:
// - Ids are UUID strings, and a record points at another by its id.
// - Days are `YYYY-MM-DD` (`LocalDate`) and moments are ISO 8601 in UTC, to the millisecond.
// - Enums are plain strings, so a value a newer build adds doesn't make the file unreadable.
// - A field that is nil is left out of the JSON, and a list is always there, even when empty.

/// One export: everything the store holds that a person would want back, as one document.
public struct CauldronExport: Sendable, Hashable, Codable {
  /// The format this build writes and reads.
  public static let currentVersion = 1

  public var formatVersion: Int
  public var exportedAt: Date
  public var app: ExportedApp
  /// Banished recipes are here too, with `deletedAt` set.
  public var recipes: [ExportedRecipe]
  public var photos: [ExportedPhoto]
  public var tags: [ExportedTag]
  public var cooks: [ExportedCook]
  public var planEntries: [ExportedPlanEntry]
  public var gatherItems: [ExportedGatherItem]
  public var pantry: [ExportedPantryItem]
  public var diary: [ExportedDiaryEntry]
  public var favourites: [ExportedFavourite]
  public var weighIns: [ExportedWeighIn]
  public var bodyProfile: ExportedBodyProfile?
  public var targets: ExportedTargets?
  public var preferences: ExportedPreferences?

  public init(
    formatVersion: Int = currentVersion, exportedAt: Date, app: ExportedApp,
    recipes: [ExportedRecipe] = [], photos: [ExportedPhoto] = [], tags: [ExportedTag] = [],
    cooks: [ExportedCook] = [], planEntries: [ExportedPlanEntry] = [],
    gatherItems: [ExportedGatherItem] = [], pantry: [ExportedPantryItem] = [],
    diary: [ExportedDiaryEntry] = [], favourites: [ExportedFavourite] = [],
    weighIns: [ExportedWeighIn] = [], bodyProfile: ExportedBodyProfile? = nil,
    targets: ExportedTargets? = nil, preferences: ExportedPreferences? = nil
  ) {
    self.formatVersion = formatVersion
    self.exportedAt = exportedAt
    self.app = app
    self.recipes = recipes
    self.photos = photos
    self.tags = tags
    self.cooks = cooks
    self.planEntries = planEntries
    self.gatherItems = gatherItems
    self.pantry = pantry
    self.diary = diary
    self.favourites = favourites
    self.weighIns = weighIns
    self.bodyProfile = bodyProfile
    self.targets = targets
    self.preferences = preferences
  }

  /// The JSON to write to the export file: indented and with sorted keys, so two exports of
  /// the same data are the same bytes and a diff between them reads.
  public func encoded() throws -> Data {
    try JSONEncoder.export().encode(self)
  }

  /// Reads an export file. A file from a newer format is refused, not half read, and a file
  /// that isn't an export at all is `unreadable`.
  public static func decode(_ data: Data) throws -> CauldronExport {
    struct Header: Decodable { var formatVersion: Int }
    let header: Header
    do {
      header = try JSONDecoder().decode(Header.self, from: data)
    } catch {
      throw ExportFormatError.unreadable
    }
    guard header.formatVersion >= 1 else { throw ExportFormatError.unreadable }
    guard header.formatVersion <= currentVersion else {
      throw ExportFormatError.newerFormat(found: header.formatVersion, supported: currentVersion)
    }
    do {
      return try JSONDecoder.export().decode(CauldronExport.self, from: data)
    } catch {
      throw ExportFormatError.unreadable
    }
  }
}

public enum ExportFormatError: Error, Hashable {
  /// The file was written by a newer build than this one understands.
  case newerFormat(found: Int, supported: Int)
  /// The file isn't JSON, or isn't an export, or is missing something version 1 always has.
  case unreadable
}

/// How moments are written. They are ISO 8601 in UTC with three decimals; the store keeps
/// finer times than that, so values are rounded to the millisecond on the way out, which is
/// also what keeps a value read back equal to the one written.
public enum ExportCoding {
  public static func milliseconds(_ date: Date) -> Date {
    Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
  }

  static func format(_ date: Date) throws -> String {
    let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
    // A date out of range can't be written (and converting it to an integer would trap).
    guard milliseconds.isFinite, abs(milliseconds) < 1e14 else {
      throw EncodingError.invalidValue(
        date, .init(codingPath: [], debugDescription: "\(date) is out of range for the export"))
    }
    let total = Int64(milliseconds)
    let seconds = Int64((Double(total) / 1000).rounded(.down))
    let wholeSeconds = Date(timeIntervalSince1970: Double(seconds))
    var text = wholeSeconds.formatted(Date.ISO8601FormatStyle())
    let millis = String(total - seconds * 1000)
    text.removeLast()  // the Z
    return text + "." + String(repeating: "0", count: 3 - millis.count) + millis + "Z"
  }

  static func parse(_ text: String) -> Date? {
    // "2026-10-11T09:30:00.123Z": the whole seconds, then exactly three digits of milliseconds.
    guard let dot = text.lastIndex(of: "."), text.hasSuffix("Z"),
      text.distance(from: dot, to: text.endIndex) == 5
    else { return nil }
    let digits = text[text.index(after: dot)..<text.index(before: text.endIndex)]
    guard digits.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
      let millis = Int64(digits),
      let whole = try? Date.ISO8601FormatStyle().parse(text[..<dot] + "Z")
    else { return nil }
    let seconds = Int64(whole.timeIntervalSince1970)
    return Date(timeIntervalSince1970: Double(seconds * 1000 + millis) / 1000)
  }
}

extension JSONEncoder {
  static func export() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(try ExportCoding.format(date))
    }
    return encoder
  }
}

extension JSONDecoder {
  static func export() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let text = try decoder.singleValueContainer().decode(String.self)
      guard let date = ExportCoding.parse(text) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "\(text) is not a moment"))
      }
      return date
    }
    return decoder
  }
}

// MARK: Parts

public struct ExportedApp: Sendable, Hashable, Codable {
  public var name: String
  /// The marketing version of the build that wrote the file.
  public var version: String?

  public init(name: String, version: String? = nil) {
    self.name = name
    self.version = version
  }
}

/// An amount, or a range from `min` to `max`.
public struct ExportedQuantity: Sendable, Hashable, Codable {
  public var min: Double
  public var max: Double?

  public init(min: Double, max: Double? = nil) {
    self.min = min
    self.max = max
  }
}

/// Per serving, and any of them can be unknown.
public struct ExportedMacros: Sendable, Hashable, Codable {
  public var calories: Double?
  public var protein: Double?
  public var carbs: Double?
  public var fat: Double?

  public init(
    calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil
  ) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }
}

// MARK: Recipes

public struct ExportedRecipe: Sendable, Hashable, Codable {
  public var id: UUID
  public var title: String
  public var summary: String?
  public var notes: String?
  public var servings: Int?
  public var prepMinutes: Int?
  public var cookMinutes: Int?
  public var totalMinutes: Int?
  public var source: ExportedSource
  public var macros: ExportedMacros
  /// `manual`, `page` or `estimated`.
  public var macrosSource: String?
  public var macrosPending: Bool
  public var ingredients: [ExportedIngredient]
  public var steps: [ExportedStep]
  public var tagIds: [UUID]
  public var lastCookedOn: LocalDate?
  /// Set on a banished recipe, which the app can still restore.
  public var deletedAt: Date?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, title: String, summary: String? = nil, notes: String? = nil, servings: Int? = nil,
    prepMinutes: Int? = nil, cookMinutes: Int? = nil, totalMinutes: Int? = nil,
    source: ExportedSource, macros: ExportedMacros, macrosSource: String? = nil,
    macrosPending: Bool, ingredients: [ExportedIngredient], steps: [ExportedStep],
    tagIds: [UUID], lastCookedOn: LocalDate? = nil, deletedAt: Date? = nil, createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.notes = notes
    self.servings = servings
    self.prepMinutes = prepMinutes
    self.cookMinutes = cookMinutes
    self.totalMinutes = totalMinutes
    self.source = source
    self.macros = macros
    self.macrosSource = macrosSource
    self.macrosPending = macrosPending
    self.ingredients = ingredients
    self.steps = steps
    self.tagIds = tagIds
    self.lastCookedOn = lastCookedOn
    self.deletedAt = deletedAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ExportedSource: Sendable, Hashable, Codable {
  /// `web`, `instagram`, `tiktok`, `manual` or `text`.
  public var platform: String
  public var url: String?
  public var author: String?
  public var fetchedAt: Date?

  public init(platform: String, url: String? = nil, author: String? = nil, fetchedAt: Date? = nil) {
    self.platform = platform
    self.url = url
    self.author = author
    self.fetchedAt = fetchedAt
  }
}

/// An ingredient line, structured: the quantity and unit as parsed, and the line as written.
public struct ExportedIngredient: Sendable, Hashable, Codable {
  public var section: String?
  public var quantity: ExportedQuantity?
  /// A unit code such as `tbsp` or `fl_oz`. A string, so a unit a newer build adds survives.
  public var unit: String?
  public var item: String
  public var note: String?
  public var optional: Bool
  public var alt: ExportedAltMeasure?
  /// The line exactly as written.
  public var original: String
  public var itemKey: String

  public init(
    section: String? = nil, quantity: ExportedQuantity? = nil, unit: String? = nil, item: String,
    note: String? = nil, optional: Bool, alt: ExportedAltMeasure? = nil, original: String,
    itemKey: String
  ) {
    self.section = section
    self.quantity = quantity
    self.unit = unit
    self.item = item
    self.note = note
    self.optional = optional
    self.alt = alt
    self.original = original
    self.itemKey = itemKey
  }
}

public struct ExportedAltMeasure: Sendable, Hashable, Codable {
  public var quantity: ExportedQuantity
  public var unit: String

  public init(quantity: ExportedQuantity, unit: String) {
    self.quantity = quantity
    self.unit = unit
  }
}

public struct ExportedStep: Sendable, Hashable, Codable {
  public var section: String?
  public var text: String
  public var timerSeconds: Int?

  public init(section: String? = nil, text: String, timerSeconds: Int? = nil) {
    self.section = section
    self.text = text
    self.timerSeconds = timerSeconds
  }
}

/// A recipe's photo. The image is in the photos archive at `file`; `file` is nil when the
/// store held no image for it.
public struct ExportedPhoto: Sendable, Hashable, Codable {
  public var id: UUID
  public var recipeId: UUID?
  public var file: String?
  public var width: Int
  public var height: Int
  public var createdAt: Date

  public init(
    id: UUID, recipeId: UUID? = nil, file: String? = nil, width: Int, height: Int, createdAt: Date
  ) {
    self.id = id
    self.recipeId = recipeId
    self.file = file
    self.width = width
    self.height = height
    self.createdAt = createdAt
  }
}

public struct ExportedTag: Sendable, Hashable, Codable {
  public var id: UUID
  public var name: String
  /// `cuisine`, `meal`, `diet` or `other`.
  public var kind: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(id: UUID, name: String, kind: String, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.name = name
    self.kind = kind
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// One day a recipe was cooked.
public struct ExportedCook: Sendable, Hashable, Codable {
  public var id: UUID
  public var recipeId: UUID?
  public var cookedOn: LocalDate
  public var createdAt: Date

  public init(id: UUID, recipeId: UUID? = nil, cookedOn: LocalDate, createdAt: Date) {
    self.id = id
    self.recipeId = recipeId
    self.cookedOn = cookedOn
    self.createdAt = createdAt
  }
}

// MARK: Plan and Gather

/// A meal on the week plan: a recipe, or free text when `recipeId` is nil.
public struct ExportedPlanEntry: Sendable, Hashable, Codable {
  public var id: UUID
  public var day: LocalDate
  /// `breakfast`, `lunch`, `dinner` or `snack`.
  public var slot: String
  public var title: String
  public var servings: Int?
  public var position: Int
  public var recipeId: UUID?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, day: LocalDate, slot: String, title: String, servings: Int? = nil, position: Int,
    recipeId: UUID? = nil, createdAt: Date, updatedAt: Date
  ) {
    self.id = id
    self.day = day
    self.slot = slot
    self.title = title
    self.servings = servings
    self.position = position
    self.recipeId = recipeId
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ExportedGatherItem: Sendable, Hashable, Codable {
  public var id: UUID
  /// The first day of the week the line belongs to.
  public var weekStart: LocalDate
  public var item: String
  public var itemKey: String
  public var quantity: ExportedQuantity?
  public var unit: String?
  public var aisle: String?
  public var checked: Bool
  /// Added by hand rather than gathered from the plan.
  public var manual: Bool
  public var position: Int
  public var sources: [ExportedGatherSource]
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, weekStart: LocalDate, item: String, itemKey: String,
    quantity: ExportedQuantity? = nil, unit: String? = nil, aisle: String? = nil, checked: Bool,
    manual: Bool, position: Int, sources: [ExportedGatherSource], createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.weekStart = weekStart
    self.item = item
    self.itemKey = itemKey
    self.quantity = quantity
    self.unit = unit
    self.aisle = aisle
    self.checked = checked
    self.manual = manual
    self.position = position
    self.sources = sources
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// How much of a Gather line one recipe asked for.
public struct ExportedGatherSource: Sendable, Hashable, Codable {
  public var id: UUID
  public var recipeId: UUID?
  public var quantity: ExportedQuantity?
  public var unit: String?

  public init(
    id: UUID, recipeId: UUID? = nil, quantity: ExportedQuantity? = nil, unit: String? = nil
  ) {
    self.id = id
    self.recipeId = recipeId
    self.quantity = quantity
    self.unit = unit
  }
}

/// Something already in the pantry, so Gather leaves it off the list.
public struct ExportedPantryItem: Sendable, Hashable, Codable {
  public var id: UUID
  public var itemKey: String
  public var createdAt: Date

  public init(id: UUID, itemKey: String, createdAt: Date) {
    self.id = id
    self.itemKey = itemKey
    self.createdAt = createdAt
  }
}

// MARK: Tracker

/// Something eaten. Its macros are the ones copied when it was logged.
public struct ExportedDiaryEntry: Sendable, Hashable, Codable {
  public var id: UUID
  public var day: LocalDate
  public var slot: String
  public var name: String
  public var amount: String?
  public var servings: Double
  public var macros: ExportedMacros
  /// `described`, `recipe` or `manual`.
  public var source: String
  public var position: Int
  public var macrosPending: Bool
  public var recipeId: UUID?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, day: LocalDate, slot: String, name: String, amount: String? = nil,
    servings: Double, macros: ExportedMacros, source: String, position: Int,
    macrosPending: Bool, recipeId: UUID? = nil, createdAt: Date, updatedAt: Date
  ) {
    self.id = id
    self.day = day
    self.slot = slot
    self.name = name
    self.amount = amount
    self.servings = servings
    self.macros = macros
    self.source = source
    self.position = position
    self.macrosPending = macrosPending
    self.recipeId = recipeId
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ExportedFavourite: Sendable, Hashable, Codable {
  public var id: UUID
  public var key: String
  public var name: String
  public var amount: String?
  public var servings: Double
  public var macros: ExportedMacros
  public var source: String
  public var recipeId: UUID?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, key: String, name: String, amount: String? = nil, servings: Double,
    macros: ExportedMacros, source: String, recipeId: UUID? = nil, createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.amount = amount
    self.servings = servings
    self.macros = macros
    self.source = source
    self.recipeId = recipeId
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ExportedWeighIn: Sendable, Hashable, Codable {
  public var id: UUID
  public var day: LocalDate
  public var weightKg: Double
  /// The HealthKit sample this came from, when it wasn't typed in.
  public var healthSampleID: String?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, day: LocalDate, weightKg: Double, healthSampleID: String? = nil, createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.day = day
    self.weightKg = weightKg
    self.healthSampleID = healthSampleID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ExportedBodyProfile: Sendable, Hashable, Codable {
  public var id: UUID
  /// `female`, `male` or `unspecified`.
  public var sex: String
  public var birthDate: LocalDate?
  public var heightCm: Double?
  /// `sedentary`, `light`, `moderate`, `active` or `veryActive`.
  public var activity: String
  /// `lose`, `maintain` or `gain`.
  public var goal: String
  public var weeklyRateKg: Double
  public var proteinPerKg: Double
  public var fatShare: Double
  /// `kg` or `lb`.
  public var weightUnit: String
  /// `cm` or `ftin`.
  public var heightUnit: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, sex: String, birthDate: LocalDate? = nil, heightCm: Double? = nil,
    activity: String, goal: String, weeklyRateKg: Double, proteinPerKg: Double, fatShare: Double,
    weightUnit: String, heightUnit: String, createdAt: Date, updatedAt: Date
  ) {
    self.id = id
    self.sex = sex
    self.birthDate = birthDate
    self.heightCm = heightCm
    self.activity = activity
    self.goal = goal
    self.weeklyRateKg = weeklyRateKg
    self.proteinPerKg = proteinPerKg
    self.fatShare = fatShare
    self.weightUnit = weightUnit
    self.heightUnit = heightUnit
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ExportedTargets: Sendable, Hashable, Codable {
  public var id: UUID
  public var calories: Int
  public var protein: Int
  public var carbs: Int
  public var fat: Int
  /// Which targets were typed in rather than calculated.
  public var overridden: ExportedTargetOverrides
  public var checkedInOn: LocalDate?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, calories: Int, protein: Int, carbs: Int, fat: Int,
    overridden: ExportedTargetOverrides, checkedInOn: LocalDate? = nil, createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
    self.overridden = overridden
    self.checkedInOn = checkedInOn
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct ExportedTargetOverrides: Sendable, Hashable, Codable {
  public var calories: Bool
  public var protein: Bool
  public var carbs: Bool
  public var fat: Bool

  public init(calories: Bool, protein: Bool, carbs: Bool, fat: Bool) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }
}

public struct ExportedPreferences: Sendable, Hashable, Codable {
  public var id: UUID
  /// The day a week starts on, numbered as `Weekday` is: 0 for Sunday, 1 for Monday, up to 6
  /// for Saturday.
  public var weekStartsOn: Int
  /// `asWritten`, `metric` or `us`.
  public var unitSystem: String
  public var createdAt: Date
  public var updatedAt: Date

  public init(id: UUID, weekStartsOn: Int, unitSystem: String, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.weekStartsOn = weekStartsOn
    self.unitSystem = unitSystem
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
