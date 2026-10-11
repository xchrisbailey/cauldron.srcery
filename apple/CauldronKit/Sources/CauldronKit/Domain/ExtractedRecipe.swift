// What every extractor produces, before it's tidied into an `ImportDraft` (`Extracted.ts` in
// the API). JSON-LD, the text reader and the model all fill this one shape, so the limits,
// the ingredient parser and the confidence flags are applied once.

public struct ExtractedLine: Sendable, Hashable, Codable {
  public var line: String
  public var section: String?
  public var unsure: Bool

  public init(line: String, section: String?, unsure: Bool) {
    self.line = line
    self.section = section
    self.unsure = unsure
  }
}

public struct ExtractedStep: Sendable, Hashable, Codable {
  public var text: String
  public var section: String?
  public var unsure: Bool

  public init(text: String, section: String?, unsure: Bool) {
    self.text = text
    self.section = section
    self.unsure = unsure
  }
}

public struct ExtractedRecipe: Sendable, Hashable, Codable {
  public var title: String?
  public var description: String?
  public var servings: Int?
  public var prepMinutes: Int?
  public var cookMinutes: Int?
  public var totalMinutes: Int?
  /// Per serving, when the source publishes it.
  public var macros: Macros?
  public var author: String?
  public var siteName: String?
  /// The page's canonical link, when it gives one.
  public var canonicalUrl: String?
  public var imageUrl: String?
  public var tags: [String]
  public var notes: String?
  public var ingredients: [ExtractedLine]
  public var steps: [ExtractedStep]
  /// Fields the extractor isn't sure about.
  public var unsure: [DraftField]

  public init(
    title: String? = nil, description: String? = nil, servings: Int? = nil,
    prepMinutes: Int? = nil, cookMinutes: Int? = nil, totalMinutes: Int? = nil,
    macros: Macros? = nil, author: String? = nil, siteName: String? = nil,
    canonicalUrl: String? = nil, imageUrl: String? = nil, tags: [String] = [],
    notes: String? = nil, ingredients: [ExtractedLine] = [], steps: [ExtractedStep] = [],
    unsure: [DraftField] = []
  ) {
    self.title = title
    self.description = description
    self.servings = servings
    self.prepMinutes = prepMinutes
    self.cookMinutes = cookMinutes
    self.totalMinutes = totalMinutes
    self.macros = macros
    self.author = author
    self.siteName = siteName
    self.canonicalUrl = canonicalUrl
    self.imageUrl = imageUrl
    self.tags = tags
    self.notes = notes
    self.ingredients = ingredients
    self.steps = steps
    self.unsure = unsure
  }

  /// Nothing read yet (`emptyExtracted` in the reference).
  public static let empty = ExtractedRecipe()
}
