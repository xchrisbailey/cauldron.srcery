import Foundation

/// The limits the recipe schemas enforced (`RECIPE_LIMITS` in `Recipe.ts`). Parsing and
/// scaling read some of them; the editor reads the rest.
public enum RecipeLimits {
  public static let title = 200
  public static let description = 2000
  public static let notes = 20_000
  public static let url = 2048
  public static let author = 200
  public static let section = 200
  public static let item = 500
  public static let note = 500
  public static let line = 1000
  public static let step = 5000
  public static let tag = 40
  public static let tags = 30
  public static let ingredients = 300
  public static let steps = 200
  public static let servings = 1000
  /// Two weeks, enough for a long ferment.
  public static let minutes = 60 * 24 * 14
  public static let timerSeconds = 60 * 60 * 72
  /// Per serving.
  public static let calories = 20_000
  /// Grams of protein, carbs or fat per serving.
  public static let grams = 2000
}

public enum SourcePlatform: String, Sendable, Hashable, Codable, CaseIterable {
  case web
  case instagram
  case tiktok
  case manual
  case text
}

public enum TagKind: String, Sendable, Hashable, Codable, CaseIterable {
  case cuisine
  case meal
  case diet
  case other
}

public struct Tag: Sendable, Hashable, Codable {
  public var id: TagId
  public var name: String
  public var kind: TagKind

  public init(id: TagId, name: String, kind: TagKind) {
    self.id = id
    self.name = name
    self.kind = kind
  }
}

public struct Step: Sendable, Hashable, Codable {
  public var section: String?
  public var text: String
  public var timerSeconds: Int?

  public init(section: String?, text: String, timerSeconds: Int?) {
    self.section = section
    self.text = text
    self.timerSeconds = timerSeconds
  }
}

/// What the library lists: enough for a card.
public struct RecipeSummary: Sendable, Hashable, Codable {
  public var id: RecipeId
  public var title: String
  public var description: String?
  public var servings: Int?
  public var prepMinutes: Int?
  public var cookMinutes: Int?
  public var totalMinutes: Int?
  /// The cover photo's key.
  public var photoKey: String?
  /// Per serving.
  public var macros: Macros
  public var tags: [Tag]
  public var lastCookedOn: LocalDate?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: RecipeId, title: String, description: String?, servings: Int?, prepMinutes: Int?,
    cookMinutes: Int?, totalMinutes: Int?, photoKey: String?, macros: Macros, tags: [Tag],
    lastCookedOn: LocalDate?, createdAt: Date, updatedAt: Date
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.servings = servings
    self.prepMinutes = prepMinutes
    self.cookMinutes = cookMinutes
    self.totalMinutes = totalMinutes
    self.photoKey = photoKey
    self.macros = macros
    self.tags = tags
    self.lastCookedOn = lastCookedOn
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct Recipe: Sendable, Hashable, Codable {
  public var id: RecipeId
  public var title: String
  public var description: String?
  public var servings: Int?
  public var prepMinutes: Int?
  public var cookMinutes: Int?
  public var totalMinutes: Int?
  public var photoKey: String?
  /// Per serving.
  public var macros: Macros
  public var tags: [Tag]
  public var lastCookedOn: LocalDate?
  public var createdAt: Date
  public var updatedAt: Date
  public var sourcePlatform: SourcePlatform
  public var sourceUrl: String?
  public var sourceAuthor: String?
  public var notes: String?
  public var ingredients: [Ingredient]
  public var steps: [Step]
  /// Set while the recipe is banished (soft deleted) and can still be restored.
  public var deletedAt: Date?

  public init(
    id: RecipeId, title: String, description: String?, servings: Int?, prepMinutes: Int?,
    cookMinutes: Int?, totalMinutes: Int?, photoKey: String?, macros: Macros, tags: [Tag],
    lastCookedOn: LocalDate?, createdAt: Date, updatedAt: Date, sourcePlatform: SourcePlatform,
    sourceUrl: String?, sourceAuthor: String?, notes: String?, ingredients: [Ingredient],
    steps: [Step], deletedAt: Date?
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.servings = servings
    self.prepMinutes = prepMinutes
    self.cookMinutes = cookMinutes
    self.totalMinutes = totalMinutes
    self.photoKey = photoKey
    self.macros = macros
    self.tags = tags
    self.lastCookedOn = lastCookedOn
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.sourcePlatform = sourcePlatform
    self.sourceUrl = sourceUrl
    self.sourceAuthor = sourceAuthor
    self.notes = notes
    self.ingredients = ingredients
    self.steps = steps
    self.deletedAt = deletedAt
  }
}
