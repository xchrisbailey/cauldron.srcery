import Foundation

/// Where an import came from. A subset of `SourcePlatform`: never manual.
public enum ImportSource: String, Sendable, Hashable, Codable, CaseIterable {
  case web
  case instagram
  case tiktok
  case text
}

public enum ImportStatus: String, Sendable, Hashable, Codable, CaseIterable {
  case queued
  case running
  case done
  case failed
  case cancelled
  case saved
}

/// Top-level draft fields an importer can flag as unsure, shown in the Tips colour.
public enum DraftField: String, Sendable, Hashable, Codable, CaseIterable {
  case title
  case description
  case servings
  case prepMinutes
  case cookMinutes
  case totalMinutes
  case macros
  case sourceUrl
  case tags
  case notes
}

public struct DraftIngredient: Sendable, Hashable, Codable {
  /// The line as the source wrote it. The editor reads it with the ingredient line parser.
  public var line: String
  public var section: String?
  /// The importer isn't sure it read this line right.
  public var unsure: Bool

  public init(line: String, section: String?, unsure: Bool) {
    self.line = line
    self.section = section
    self.unsure = unsure
  }
}

public struct DraftStep: Sendable, Hashable, Codable {
  public var text: String
  public var section: String?
  public var unsure: Bool

  public init(text: String, section: String?, unsure: Bool) {
    self.text = text
    self.section = section
    self.unsure = unsure
  }
}

/// A recipe as an importer read it, ready to open in the editor. Nothing here is validated as a
/// recipe until the cook saves it.
public struct ImportDraft: Sendable, Hashable, Codable {
  public var title: String
  public var description: String?
  public var servings: Int?
  public var prepMinutes: Int?
  public var cookMinutes: Int?
  public var totalMinutes: Int?
  /// Per serving, when the source published it.
  public var macros: Macros?
  public var sourcePlatform: ImportSource
  public var sourceUrl: String?
  public var sourceAuthor: String?
  /// The site or account the recipe came from, for attribution.
  public var siteName: String?
  public var notes: String?
  /// A cover photo the importer fetched.
  public var photoKey: String?
  public var tags: [String]
  public var ingredients: [DraftIngredient]
  public var steps: [DraftStep]
  /// Fields to confirm before saving.
  public var unsure: [DraftField]

  public init(
    title: String, description: String?, servings: Int?, prepMinutes: Int?, cookMinutes: Int?,
    totalMinutes: Int?, macros: Macros?, sourcePlatform: ImportSource, sourceUrl: String?,
    sourceAuthor: String?, siteName: String?, notes: String?, photoKey: String?, tags: [String],
    ingredients: [DraftIngredient], steps: [DraftStep], unsure: [DraftField]
  ) {
    self.title = title
    self.description = description
    self.servings = servings
    self.prepMinutes = prepMinutes
    self.cookMinutes = cookMinutes
    self.totalMinutes = totalMinutes
    self.macros = macros
    self.sourcePlatform = sourcePlatform
    self.sourceUrl = sourceUrl
    self.sourceAuthor = sourceAuthor
    self.siteName = siteName
    self.notes = notes
    self.photoKey = photoKey
    self.tags = tags
    self.ingredients = ingredients
    self.steps = steps
    self.unsure = unsure
  }
}

/// Why an import failed. Each has a plain message in `Copy.imports`.
public enum ImportFailureCode: String, Sendable, Hashable, Codable, CaseIterable {
  case couldntRead
  case noRecipe
  case spokenOnly
  case tooLarge
  case blocked
  case timeout
  case unavailable
}

public struct ImportFailure: Sendable, Hashable, Codable {
  public var code: ImportFailureCode
  public var message: String

  public init(code: ImportFailureCode, message: String) {
    self.code = code
    self.message = message
  }
}

/// A live recipe already in the box from the same link.
public struct ImportDuplicate: Sendable, Hashable, Codable {
  public var id: RecipeId
  public var title: String

  public init(id: RecipeId, title: String) {
    self.id = id
    self.title = title
  }
}

public struct ImportJob: Sendable, Hashable, Codable {
  public var id: ImportId
  public var status: ImportStatus
  public var source: ImportSource
  public var sourceUrl: String?
  /// Set when the job is done.
  public var draft: ImportDraft?
  /// Set when the job failed.
  public var failure: ImportFailure?
  public var duplicateOf: ImportDuplicate?
  /// The recipe the draft was saved as.
  public var recipeId: RecipeId?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: ImportId, status: ImportStatus, source: ImportSource, sourceUrl: String?,
    draft: ImportDraft?, failure: ImportFailure?, duplicateOf: ImportDuplicate?,
    recipeId: RecipeId?, createdAt: Date, updatedAt: Date
  ) {
    self.id = id
    self.status = status
    self.source = source
    self.sourceUrl = sourceUrl
    self.draft = draft
    self.failure = failure
    self.duplicateOf = duplicateOf
    self.recipeId = recipeId
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
