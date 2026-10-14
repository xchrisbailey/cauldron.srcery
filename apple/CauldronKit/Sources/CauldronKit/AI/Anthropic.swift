import Foundation

// Anthropic's Messages API (`POST /v1/messages`) with a strict JSON Schema as the output format.
// Like `Gemini`, this builds requests and reads responses as plain data; the app supplies the
// key and the connection.

public enum Anthropic {
  /// Claude Haiku 5.5: these are small, frequent extraction jobs, and it costs a fortieth of
  /// Claude Opus 5.5. The cook can name another model in Settings.
  public static let defaultModel = "claude-haiku-5-5"
  /// The URL is fixed. The model name goes in the body, so it can't change where a request goes.
  public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")
  public static let version = "2023-06-01"
  /// Opts in to the server-side fallback that the request body asks for.
  public static let beta = "server-side-fallback-2026-07-01"
  /// The models that take `fallbacks: "default"`. Others, Claude Haiku 5.5 among them, have no
  /// server-side fallback, so their requests go without it.
  static let modelsWithFallback: Set<String> = [
    "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
  ]

  /// A request for `task`. The key goes in its `x-api-key` header and nowhere else.
  ///
  /// Current Claude models reject `thinking: disabled`, `temperature`, `top_p` and a prefilled
  /// assistant message, so none of them is sent. On the models that support it, `fallbacks` lets
  /// Anthropic's servers answer with another model if this one declines.
  public static func request(
    for task: AITask, model: String, key: String
  ) throws(RecipeAIError) -> AIRequest {
    guard !model.isEmpty else { throw .invalidModel }
    guard let url = endpoint else { throw .failed(detail: "request") }
    let prompt = task.prompt
    let body = RequestBody(
      model: model, maxTokens: 16000, system: prompt.system,
      messages: [.init(role: "user", content: prompt.user)],
      outputConfig: .init(
        effort: "low",
        format: .init(type: "json_schema", schema: task.schema.strictJSONSchema)),
      fallbacks: modelsWithFallback.contains(model) ? "default" : nil)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(body) else { throw .failed(detail: "request") }
    var headers = [
      "x-api-key": key, "anthropic-version": version, "content-type": "application/json",
    ]
    if body.fallbacks != nil { headers["anthropic-beta"] = beta }
    return AIRequest(url: url, headers: headers, body: data)
  }

  public static func answer(status: Int, body: Data) throws(RecipeAIError) -> AIAnswer {
    guard (200..<300).contains(status) else { throw error(status: status, body: body) }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let response = try? decoder.decode(ResponseBody.self, from: body) else {
      throw .failed(detail: "unreadable response")
    }
    switch response.stopReason {
    case "refusal": throw .failed(detail: "refused")
    case "max_tokens": throw .failed(detail: "too long")
    default: break
    }
    // Other kinds of block can come first, so the answer is every text block, not the first.
    let text = (response.content ?? []).filter { $0.type == "text" }.compactMap(\.text).joined()
    guard !text.isEmpty else { throw .failed(detail: "empty answer") }
    return AIAnswer(
      json: Data(text.utf8),
      inputTokens: response.usage?.inputTokens ?? 0,
      outputTokens: response.usage?.outputTokens ?? 0)
  }

  /// What a refusal means. A bad key is 401 or 403, a spent balance is 402 (`billing_error`)
  /// and counts as a limit, 429 is a limit, and a model it doesn't know is 404. 529
  /// (`overloaded_error`) and the server errors are reasons to wait. Only a request it
  /// understood and rejected is a failure, and that says what kind with the error's `type`,
  /// never its message.
  static func error(status: Int, body: Data) -> RecipeAIError {
    switch status {
    case 401, 403: return .invalidKey
    case 402, 429: return .rateLimited
    case 404: return .invalidModel
    // A timeout, a status that isn't HTTP at all, and 529 among the server errors.
    case 408, ..<100, 500...599: return .unreachable
    case 400..<500:
      let failure = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
      guard let type = failure?.type else { return .failed(detail: "status \(status)") }
      return .failed(detail: "rejected: \(type.prefix(64))")
    default:
      return .failed(detail: "status \(status)")
    }
  }

  // MARK: Wire shapes

  struct RequestBody: Encodable {
    struct Message: Encodable {
      let role: String
      let content: String
    }
    struct OutputConfig: Encodable {
      struct Format: Encodable {
        let type: String
        let schema: AISchema.StrictJSONSchema
      }
      let effort: String
      let format: Format
    }
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]
    let outputConfig: OutputConfig
    let fallbacks: String?

    // Spelled out: a key strategy would also rewrite the schema's own property names.
    private enum CodingKeys: String, CodingKey {
      case model, system, messages, fallbacks
      case maxTokens = "max_tokens"
      case outputConfig = "output_config"
    }
  }

  struct ResponseBody: Decodable {
    struct Block: Decodable {
      let type: String?
      let text: String?
    }
    struct Usage: Decodable {
      let inputTokens: Int?
      let outputTokens: Int?
    }
    let content: [Block]?
    let stopReason: String?
    let usage: Usage?
  }

  struct ErrorBody: Decodable {
    struct Failure: Decodable { let type: String? }
    let error: Failure
  }
}
