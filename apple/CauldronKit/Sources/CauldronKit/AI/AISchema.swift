import Foundation

/// The shape of a model's answer, written once. Encoding it renders Gemini's `responseSchema`
/// (the subset of OpenAPI that Gemini takes); `strictJSONSchema` renders the strict JSON Schema
/// that OpenAI and Anthropic take.
public indirect enum AISchema: Sendable, Hashable, Encodable {
  case string(description: String? = nil, nullable: Bool = false, values: [String]? = nil)
  case number(description: String? = nil, nullable: Bool = false)
  case boolean(description: String? = nil)
  case array(of: AISchema, description: String? = nil)
  /// Every property is required, and they are answered in the order given.
  case object([(String, AISchema)])

  public static func == (lhs: AISchema, rhs: AISchema) -> Bool {
    lhs.canonical == rhs.canonical
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(canonical)
  }

  private var canonical: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
  }

  private enum Key: String, CodingKey {
    case type, description, nullable, items, properties, required, propertyOrdering
    case additionalProperties
    case values = "enum"
  }

  private struct Name: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    switch self {
    case .string(let description, let nullable, let values):
      try container.encode("STRING", forKey: .type)
      try container.encodeIfPresent(description, forKey: .description)
      if nullable { try container.encode(true, forKey: .nullable) }
      try container.encodeIfPresent(values, forKey: .values)
    case .number(let description, let nullable):
      try container.encode("NUMBER", forKey: .type)
      try container.encodeIfPresent(description, forKey: .description)
      if nullable { try container.encode(true, forKey: .nullable) }
    case .boolean(let description):
      try container.encode("BOOLEAN", forKey: .type)
      try container.encodeIfPresent(description, forKey: .description)
    case .array(let items, let description):
      try container.encode("ARRAY", forKey: .type)
      try container.encodeIfPresent(description, forKey: .description)
      try container.encode(items, forKey: .items)
    case .object(let properties):
      try container.encode("OBJECT", forKey: .type)
      var nested = container.nestedContainer(keyedBy: Name.self, forKey: .properties)
      for (name, schema) in properties { try nested.encode(schema, forKey: Name(name)) }
      let names = properties.map(\.0)
      try container.encode(names, forKey: .required)
      try container.encode(names, forKey: .propertyOrdering)
    }
  }
}

extension AISchema {
  /// The schema as strict JSON Schema: every object closes with `additionalProperties: false`
  /// and lists every property as required, and a nullable field says `["string", "null"]`.
  public var strictJSONSchema: StrictJSONSchema { StrictJSONSchema(schema: self) }

  public struct StrictJSONSchema: Sendable, Encodable {
    let schema: AISchema

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: Key.self)
      switch schema {
      case .string(let description, let nullable, let values):
        try Self.encodeType("string", nullable: nullable, in: &container)
        try container.encodeIfPresent(description, forKey: .description)
        // A nullable field's enum has to allow the null it is allowed to answer.
        if let values {
          let allowed: [String?] = nullable ? values + [nil] : values
          try container.encode(allowed, forKey: .values)
        }
      case .number(let description, let nullable):
        try Self.encodeType("number", nullable: nullable, in: &container)
        try container.encodeIfPresent(description, forKey: .description)
      case .boolean(let description):
        try container.encode("boolean", forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
      case .array(let items, let description):
        try container.encode("array", forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(StrictJSONSchema(schema: items), forKey: .items)
      case .object(let properties):
        try container.encode("object", forKey: .type)
        var nested = container.nestedContainer(keyedBy: Name.self, forKey: .properties)
        for (name, child) in properties {
          try nested.encode(StrictJSONSchema(schema: child), forKey: Name(name))
        }
        try container.encode(properties.map(\.0), forKey: .required)
        try container.encode(false, forKey: .additionalProperties)
      }
    }

    /// `"string"`, or `["string", "null"]` for a field that may be null.
    private static func encodeType(
      _ name: String, nullable: Bool, in container: inout KeyedEncodingContainer<Key>
    ) throws {
      if nullable {
        try container.encode([name, "null"], forKey: .type)
      } else {
        try container.encode(name, forKey: .type)
      }
    }
  }
}

// The schemas, with the descriptions the reference gives the model.
extension AISchema {
  private static let minutes = AISchema.number(
    description: "Whole minutes, or null.", nullable: true)

  static let recipe = AISchema.object([
    (
      "recipe",
      .string(
        description:
          "\"found\" when the text has a recipe (ingredients and method). \"inVideo\" when it only points to a recipe shown or spoken in a video. \"missing\" otherwise.",
        values: ExtractOutcome.allCases.map(\.rawValue))
    ),
    ("title", .string(nullable: true)),
    (
      "description",
      .string(
        description:
          "One or two sentences about the dish from the text, or null. Never invent one.",
        nullable: true)
    ),
    ("servings", .number(nullable: true)),
    ("prepMinutes", minutes),
    ("cookMinutes", minutes),
    ("totalMinutes", minutes),
    (
      "ingredients",
      .array(
        of: .object([
          (
            "line",
            .string(
              description: "The ingredient line exactly as written, quantity and unit included.")
          ),
          (
            "section",
            .string(
              description: "The heading it sits under, like \"For the sauce\", or null.",
              nullable: true)
          ),
          (
            "unsure",
            .boolean(description: "True when you had to guess at this line or it may be misread.")
          ),
        ]))
    ),
    (
      "steps",
      .array(
        of: .object([
          ("text", .string(description: "One step of the method, as written.")),
          ("section", .string(nullable: true)),
          ("unsure", .boolean()),
        ]))
    ),
    (
      "tags",
      .array(
        of: .string(),
        description:
          "Up to five short tags already implied by the text, like a cuisine or a diet.")
    ),
    (
      "notes",
      .string(
        description: "Tips, storage or substitutions from the text, or null.", nullable: true)
    ),
    (
      "unsure",
      .array(
        of: .string(values: DraftField.allCases.map(\.rawValue)),
        description: "Top-level fields you guessed or aren't sure of.")
    ),
  ])

  static let macros = AISchema.object([
    (
      "servings",
      .number(
        description:
          "The servings you divided by: the given yield, or your own guess when none was given.",
        nullable: true)
    ),
    ("calories", .number(description: "Kilocalories per serving.", nullable: true)),
    ("protein", .number(description: "Grams of protein per serving.", nullable: true)),
    ("carbs", .number(description: "Grams of carbohydrate per serving.", nullable: true)),
    ("fat", .number(description: "Grams of fat per serving.", nullable: true)),
  ])

  static let meal = AISchema.object([
    (
      "items",
      .array(
        of: .object([
          (
            "name",
            .string(description: "The food, short and plain: \"Eggs\", \"Sourdough\".")
          ),
          (
            "amount",
            .string(
              description:
                "How much, as the cook said it or a typical portion: \"2 large\", \"1 slice\". Null if unknown.",
              nullable: true)
          ),
          (
            "food",
            .boolean(
              description:
                "False when this isn't something eaten or drunk; its numbers must then be null.")
          ),
          ("calories", .number(description: "Kilocalories for that amount.", nullable: true)),
          ("protein", .number(description: "Grams of protein for that amount.", nullable: true)),
          (
            "carbs", .number(description: "Grams of carbohydrate for that amount.", nullable: true)
          ),
          ("fat", .number(description: "Grams of fat for that amount.", nullable: true)),
        ]))
    )
  ])
}
