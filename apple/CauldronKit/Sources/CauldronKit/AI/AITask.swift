import Foundation

/// The three things asked of a model, each with its prompt and the shape of its answer. Every
/// provider is asked the same way; only the request around it differs.
public enum AITask: Sendable, Hashable {
  case extract(ExtractInput)
  case macros(MacroEstimateInput)
  case meal(String)

  public var prompt: AIPrompt {
    switch self {
    case .extract(let input): AIPrompts.extract(input)
    case .macros(let input): AIPrompts.macros(input)
    case .meal(let text): AIPrompts.meal(text)
    }
  }

  public var schema: AISchema {
    switch self {
    case .extract: .recipe
    case .macros: .macros
    case .meal: .meal
    }
  }

  /// What the schema is called, for the providers that name it. Letters only, as they require.
  public var schemaName: String {
    switch self {
    case .extract: "recipe"
    case .macros: "macros"
    case .meal: "meal"
    }
  }
}

/// The model's JSON answer and what it cost, once a provider's response has been read.
public struct AIAnswer: Sendable, Hashable {
  public var json: Data
  public var inputTokens: Int
  public var outputTokens: Int

  public init(json: Data, inputTokens: Int, outputTokens: Int) {
    self.json = json
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }

  /// Decodes the answer for a task. An answer that doesn't fit is a failure.
  func decode<T: Decodable>(_ type: T.Type) throws(RecipeAIError) -> T {
    guard let value = try? JSONDecoder().decode(type, from: json) else {
      throw .failed(detail: "bad output")
    }
    return value
  }

  public func extraction(model: String) throws(RecipeAIError) -> Extraction {
    let recipe = try decode(ModelRecipe.self)
    return Extraction(
      outcome: recipe.recipe, recipe: recipe.extracted,
      usage: AIUsage(model: model, inputTokens: inputTokens, outputTokens: outputTokens))
  }

  public func macros() throws(RecipeAIError) -> Macros {
    try decode(ModelMacros.self).macros
  }

  public func meal() throws(RecipeAIError) -> [DescribedItem] {
    try decode(ModelMeal.self).described
  }
}

/// A request ready to post: where, with which headers, and what body. The key is in its header
/// and nowhere else.
public struct AIRequest: Sendable, Hashable {
  public var url: URL
  public var headers: [String: String]
  public var body: Data

  public init(url: URL, headers: [String: String], body: Data) {
    self.url = url
    self.headers = headers
    self.body = body
  }
}
