import Foundation

// Gemini's REST API (`models/{model}:generateContent`) with structured JSON output. This file
// builds request bodies and reads responses as plain data, so it tests on Linux; the app
// supplies the key and the connection.

public enum Gemini {
  public static let defaultModel = "gemini-3.5-flash-lite"
  /// The header that carries the key. It never goes in the URL, where it could be logged.
  public static let keyHeader = "x-goog-api-key"

  /// Where a request for `model` is posted, or nil when the model name can't be part of a URL.
  public static func endpoint(model: String) -> URL? {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
    guard !model.isEmpty, model.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
    return URL(
      string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
  }

  /// The three things asked of the model, each with its prompt and the shape of its answer.
  public enum Task: Sendable, Hashable {
    case extract(ExtractInput)
    case macros(MacroEstimateInput)
    case meal(String)

    var prompt: AIPrompt {
      switch self {
      case .extract(let input): AIPrompts.extract(input)
      case .macros(let input): AIPrompts.macros(input)
      case .meal(let text): AIPrompts.meal(text)
      }
    }

    var schema: GeminiSchema {
      switch self {
      case .extract: .recipe
      case .macros: .macros
      case .meal: .meal
      }
    }
  }

  /// The JSON body of a request.
  public static func requestBody(for task: Task) throws -> Data {
    let prompt = task.prompt
    let body = RequestBody(
      systemInstruction: .init(role: nil, parts: [.init(text: prompt.system)]),
      contents: [.init(role: "user", parts: [.init(text: prompt.user)])],
      generationConfig: .init(responseMimeType: "application/json", responseSchema: task.schema))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(body)
  }

  /// The model's JSON answer and what it cost, from a response's status and body.
  public struct Answer: Sendable, Hashable {
    public var json: Data
    public var inputTokens: Int
    public var outputTokens: Int
  }

  public static func answer(status: Int, body: Data) throws(RecipeAIError) -> Answer {
    guard (200..<300).contains(status) else { throw error(status: status, body: body) }
    guard let response = try? JSONDecoder().decode(ResponseBody.self, from: body) else {
      throw .failed(detail: "unreadable response")
    }
    if let reason = response.promptFeedback?.blockReason {
      throw .failed(detail: "blocked: \(reason)")
    }
    guard let candidate = response.candidates?.first else {
      throw .failed(detail: "no answer")
    }
    let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
    // Anything but a clean stop (a length cut, a safety stop) leaves JSON that can't be trusted.
    if let reason = candidate.finishReason, reason != "STOP" {
      throw .failed(detail: "stopped: \(reason)")
    }
    guard !text.isEmpty else { throw .failed(detail: "empty answer") }
    return Answer(
      json: Data(text.utf8),
      inputTokens: response.usageMetadata?.promptTokenCount ?? 0,
      outputTokens: response.usageMetadata?.candidatesTokenCount ?? 0)
  }

  /// What a refusal means. Gemini reports a bad key as 400 with `API_KEY_INVALID`, or as 401
  /// or 403, and a model it doesn't know as 404. Only a request it understood and rejected is
  /// a failure; the rest are reasons to wait.
  static func error(status: Int, body: Data) -> RecipeAIError {
    let failure = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
    switch status {
    case 429: return .rateLimited
    case 401, 403: return .invalidKey
    case 404: return .invalidModel
    // A timeout, or a status that isn't HTTP at all.
    case 408, ..<100, 500...599: return .unreachable
    case 400:
      let reasons = (failure?.details ?? []).compactMap(\.reason)
      let message = failure?.message ?? ""
      if reasons.contains("API_KEY_INVALID") || message.contains("API key not valid") {
        return .invalidKey
      }
      return .failed(detail: "rejected: \(failure?.status ?? "400")")
    default:
      return .failed(detail: "status \(status)")
    }
  }

  /// Decodes the model's answer for a task. An answer that doesn't fit is a failure.
  static func decode<T: Decodable>(_ type: T.Type, from answer: Answer) throws(RecipeAIError) -> T {
    guard let value = try? JSONDecoder().decode(type, from: answer.json) else {
      throw .failed(detail: "bad output")
    }
    return value
  }

  public static func extraction(from answer: Answer, model: String) throws(RecipeAIError)
    -> Extraction
  {
    let recipe = try decode(ModelRecipe.self, from: answer)
    return Extraction(
      outcome: recipe.recipe, recipe: recipe.extracted,
      usage: AIUsage(
        model: model, inputTokens: answer.inputTokens, outputTokens: answer.outputTokens))
  }

  public static func macros(from answer: Answer) throws(RecipeAIError) -> Macros {
    try decode(ModelMacros.self, from: answer).macros
  }

  public static func meal(from answer: Answer) throws(RecipeAIError) -> [DescribedItem] {
    try decode(ModelMeal.self, from: answer).described
  }

  // MARK: Wire shapes

  struct RequestBody: Encodable {
    struct Content: Encodable {
      struct Part: Encodable { let text: String }
      let role: String?
      let parts: [Part]
    }
    struct GenerationConfig: Encodable {
      let responseMimeType: String
      let responseSchema: GeminiSchema
    }
    let systemInstruction: Content
    let contents: [Content]
    let generationConfig: GenerationConfig
  }

  struct ResponseBody: Decodable {
    struct Candidate: Decodable {
      struct Content: Decodable {
        struct Part: Decodable { let text: String? }
        let parts: [Part]?
      }
      let content: Content?
      let finishReason: String?
    }
    struct Feedback: Decodable { let blockReason: String? }
    struct Usage: Decodable {
      let promptTokenCount: Int?
      let candidatesTokenCount: Int?
    }
    let candidates: [Candidate]?
    let promptFeedback: Feedback?
    let usageMetadata: Usage?
  }

  struct ErrorBody: Decodable {
    struct Failure: Decodable {
      struct Detail: Decodable { let reason: String? }
      let message: String?
      let status: String?
      let details: [Detail]?
    }
    let error: Failure
  }
}

/// A `responseSchema`: the subset of OpenAPI that Gemini's structured output takes.
public indirect enum GeminiSchema: Sendable, Hashable, Encodable {
  case string(description: String? = nil, nullable: Bool = false, values: [String]? = nil)
  case number(description: String? = nil, nullable: Bool = false)
  case boolean(description: String? = nil)
  case array(of: GeminiSchema, description: String? = nil)
  /// Every property is required, and they are answered in the order given.
  case object([(String, GeminiSchema)])

  public static func == (lhs: GeminiSchema, rhs: GeminiSchema) -> Bool {
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

// The schemas, with the descriptions the reference gives the model.
extension GeminiSchema {
  private static let minutes = GeminiSchema.number(
    description: "Whole minutes, or null.", nullable: true)

  static let recipe = GeminiSchema.object([
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

  static let macros = GeminiSchema.object([
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

  static let meal = GeminiSchema.object([
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
