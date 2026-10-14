import Foundation

// OpenAI's Responses API (`POST /v1/responses`) with a strict JSON Schema as the output format.
// Like `Gemini`, this builds requests and reads responses as plain data; the app supplies the
// key and the connection.

public enum OpenAI {
  public static let defaultModel = "gpt-6-luna"
  /// The URL is fixed. The model name goes in the body, so it can't change where a request goes.
  public static let endpoint = URL(string: "https://api.openai.com/v1/responses")

  /// A request for `task`. The key goes in its `Authorization` header and nowhere else.
  public static func request(
    for task: AITask, model: String, key: String
  ) throws(RecipeAIError) -> AIRequest {
    guard !model.isEmpty else { throw .invalidModel }
    guard let url = endpoint else { throw .failed(detail: "request") }
    let prompt = task.prompt
    let body = RequestBody(
      model: model, instructions: prompt.system, input: prompt.user,
      text: .init(
        format: .init(
          type: "json_schema", name: task.schemaName, strict: true,
          schema: task.schema.strictJSONSchema)),
      store: false)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(body) else { throw .failed(detail: "request") }
    return AIRequest(
      url: url,
      headers: ["Authorization": "Bearer \(key)", "Content-Type": "application/json"],
      body: data)
  }

  public static func answer(status: Int, body: Data) throws(RecipeAIError) -> AIAnswer {
    guard (200..<300).contains(status) else { throw error(status: status, body: body) }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let response = try? decoder.decode(ResponseBody.self, from: body) else {
      throw .failed(detail: "unreadable response")
    }
    // An unfinished response (cut short, or one that failed) leaves JSON that can't be trusted.
    guard response.status == "completed" else {
      throw .failed(
        detail: "stopped: \(response.incompleteDetails?.reason ?? response.status ?? "unknown")")
    }
    guard let message = response.output?.first(where: { $0.type == "message" }) else {
      throw .failed(detail: "no answer")
    }
    let parts = message.content ?? []
    if parts.contains(where: { $0.type == "refusal" }) { throw .failed(detail: "refused") }
    let text = parts.filter { $0.type == "output_text" }.compactMap(\.text).joined()
    guard !text.isEmpty else { throw .failed(detail: "empty answer") }
    return AIAnswer(
      json: Data(text.utf8),
      inputTokens: response.usage?.inputTokens ?? 0,
      outputTokens: response.usage?.outputTokens ?? 0)
  }

  /// What a refusal means. A bad key is 401 or 403, a spent quota is 429, an account with no
  /// credit is 429 with the code `insufficient_quota`, and a model it doesn't know is 404.
  /// Only a request it understood and rejected is a failure, and that says what kind with the
  /// error's `code` or `type`, never its message, which can quote the request.
  static func error(status: Int, body: Data) -> RecipeAIError {
    switch status {
    case 401, 403: return .invalidKey
    case 429:
      let failure = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
      return failure?.code == "insufficient_quota" || failure?.type == "insufficient_quota"
        ? .noCredit : .rateLimited
    case 404: return .invalidModel
    // A timeout, or a status that isn't HTTP at all.
    case 408, ..<100, 500...599: return .unreachable
    case 400..<500:
      let failure = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
      guard let reason = failure?.code ?? failure?.type else {
        return .failed(detail: "status \(status)")
      }
      return .failed(detail: "rejected: \(reason.prefix(64))")
    default:
      return .failed(detail: "status \(status)")
    }
  }

  // MARK: Wire shapes

  struct RequestBody: Encodable {
    struct Text: Encodable {
      struct Format: Encodable {
        let type: String
        let name: String
        let strict: Bool
        let schema: AISchema.StrictJSONSchema
      }
      let format: Format
    }
    let model: String
    let instructions: String
    let input: String
    let text: Text
    let store: Bool
  }

  struct ResponseBody: Decodable {
    struct Item: Decodable {
      struct Part: Decodable {
        let type: String?
        let text: String?
      }
      let type: String?
      let content: [Part]?
    }
    struct Incomplete: Decodable { let reason: String? }
    struct Usage: Decodable {
      let inputTokens: Int?
      let outputTokens: Int?
    }
    let status: String?
    let incompleteDetails: Incomplete?
    let output: [Item]?
    let usage: Usage?
  }

  struct ErrorBody: Decodable {
    struct Failure: Decodable {
      let type: String?
      let code: String?
    }
    let error: Failure
  }
}
