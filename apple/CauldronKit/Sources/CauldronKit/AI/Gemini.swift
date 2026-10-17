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

  /// A request for `task`. The key goes in its header and nowhere else.
  public static func request(
    for task: AITask, model: String, key: String
  ) throws(RecipeAIError) -> AIRequest {
    guard let url = endpoint(model: model) else { throw .invalidModel }
    guard let body = try? requestBody(for: task) else { throw .failed(detail: "request") }
    return AIRequest(
      url: url, headers: ["Content-Type": "application/json", keyHeader: key], body: body)
  }

  /// The JSON body of a request.
  public static func requestBody(for task: AITask) throws -> Data {
    let prompt = task.prompt
    let body = RequestBody(
      systemInstruction: .init(role: nil, parts: [.init(text: prompt.system)]),
      contents: [.init(role: "user", parts: [.init(text: prompt.user)])],
      generationConfig: .init(responseMimeType: "application/json", responseSchema: task.schema))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(body)
  }

  public static func answer(status: Int, body: Data) throws(RecipeAIError) -> AIAnswer {
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
    return AIAnswer(
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

  // MARK: Wire shapes

  struct RequestBody: Encodable {
    struct Content: Encodable {
      struct Part: Encodable { let text: String }
      let role: String?
      let parts: [Part]
    }
    struct GenerationConfig: Encodable {
      let responseMimeType: String
      let responseSchema: AISchema
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
