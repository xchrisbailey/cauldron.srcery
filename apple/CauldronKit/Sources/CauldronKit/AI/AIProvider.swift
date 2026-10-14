import Foundation

/// The services Cauldron can ask, each with the cook's own key. Which one is in use is the
/// app's business; callers of `RecipeAI` never see it.
public enum AIProvider: String, CaseIterable, Sendable, Codable, Identifiable {
  public var id: String { rawValue }

  case gemini
  case openai
  case anthropic

  /// What the cook sees: "Gemini", "OpenAI", "Claude".
  public var displayName: String {
    Copy.settings.ai.providerName(self).text
  }

  /// Where the cook makes a key for this provider.
  public var keyPage: URL? {
    switch self {
    case .gemini: URL(string: "https://aistudio.google.com/apikey")
    case .openai: URL(string: "https://platform.openai.com/api-keys")
    case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
    }
  }

  public var defaultModel: String {
    switch self {
    case .gemini: Gemini.defaultModel
    case .openai: OpenAI.defaultModel
    case .anthropic: Anthropic.defaultModel
    }
  }

  /// The request for `task` on `model` with `key`. An empty model name is refused, and so is a
  /// blank key. The key travels in a header and nowhere else, and is in no error.
  public func request(
    for task: AITask, model: String, key: String
  ) throws(RecipeAIError) -> AIRequest {
    guard !key.isEmpty else { throw .missingKey }
    switch self {
    case .gemini: return try Gemini.request(for: task, model: model, key: key)
    case .openai: return try OpenAI.request(for: task, model: model, key: key)
    case .anthropic: return try Anthropic.request(for: task, model: model, key: key)
    }
  }

  /// The model's answer from a response's status and body, or why there isn't one.
  public func answer(status: Int, body: Data) throws(RecipeAIError) -> AIAnswer {
    switch self {
    case .gemini: try Gemini.answer(status: status, body: body)
    case .openai: try OpenAI.answer(status: status, body: body)
    case .anthropic: try Anthropic.answer(status: status, body: body)
    }
  }
}
