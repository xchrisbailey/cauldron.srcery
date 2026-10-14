import CauldronKit
import Foundation
import Testing

// The response bodies here are written by hand from OpenAI's documented Responses API shapes.
// They have not been recorded from the live API.

private let secret = "sk-test-secret-123"

private func object(_ data: Data) throws -> [String: Any] {
  try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func json(_ value: Any) -> Data {
  try! JSONSerialization.data(withJSONObject: value)
}

/// A finished response whose message holds `parts`, after a reasoning item that has no content.
private func response(
  parts: [[String: Any]], status: String = "completed", incomplete: String? = nil
) -> Data {
  var body: [String: Any] = [
    "id": "resp_123", "object": "response", "status": status, "model": "gpt-6-luna",
    "output": [
      ["type": "reasoning", "id": "rs_1", "summary": []],
      [
        "type": "message", "id": "msg_1", "status": "completed", "role": "assistant",
        "content": parts,
      ],
    ],
    "usage": ["input_tokens": 640, "output_tokens": 97, "total_tokens": 737],
  ]
  if let incomplete { body["incomplete_details"] = ["reason": incomplete] }
  return json(body)
}

private func response(text: String) -> Data {
  response(parts: [["type": "output_text", "text": text, "annotations": []]])
}

private func failure(type: String? = nil, code: String? = nil, message: String = "nope") -> Data {
  var error: [String: Any] = ["message": message]
  if let type { error["type"] = type }
  if let code { error["code"] = code }
  return json(["error": error])
}

@Suite("OpenAI requests")
struct OpenAIRequestTests {
  @Test func theRequestGoesToAFixedURLWithTheKeyInItsHeaderOnly() throws {
    let request = try AIProvider.openai.request(
      for: .meal("eggs on toast"), model: "gpt-test", key: secret)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.url.query == nil)
    #expect(request.headers["Authorization"] == "Bearer \(secret)")
    #expect(request.headers["Content-Type"] == "application/json")
    #expect(request.headers.count == 2)
    #expect(!request.url.absoluteString.contains(secret))
    #expect(!String(decoding: request.body, as: UTF8.self).contains(secret))
  }

  @Test func theBodyCarriesThePromptAndAStrictSchema() throws {
    let input = ExtractInput(text: "2 eggs. Fry them.", kind: .text)
    let request = try AIProvider.openai.request(
      for: .extract(input), model: "gpt-test", key: secret)
    let body = try object(request.body)
    #expect(body["model"] as? String == "gpt-test")
    #expect(body["instructions"] as? String == AIPrompts.extract(input).system)
    #expect(body["input"] as? String == "2 eggs. Fry them.")
    #expect(body["store"] as? Bool == false)
    #expect(Set(body.keys) == ["model", "instructions", "input", "text", "store"])

    let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
    #expect(format["type"] as? String == "json_schema")
    #expect(format["name"] as? String == "recipe")
    #expect(format["strict"] as? Bool == true)
    let schema = try #require(format["schema"] as? [String: Any])
    #expect(schema["type"] as? String == "object")
    #expect(schema["additionalProperties"] as? Bool == false)
    #expect((schema["required"] as? [String])?.count == 12)
    let properties = try #require(schema["properties"] as? [String: [String: Any]])
    #expect(properties["title"]?["type"] as? [String] == ["string", "null"])
    #expect(properties["recipe"]?["enum"] as? [String] == ["found", "missing", "inVideo"])
  }

  @Test func eachTaskNamesItsSchema() throws {
    func name(_ task: AITask) throws -> String? {
      let body = try object(AIProvider.openai.request(for: task, model: "m", key: secret).body)
      return ((body["text"] as? [String: Any])?["format"] as? [String: Any])?["name"] as? String
    }
    #expect(
      try name(.macros(MacroEstimateInput(title: nil, servings: nil, ingredients: []))) == "macros")
    #expect(try name(.meal("x")) == "meal")
  }

  @Test func aRequestIsTheSameEveryTime() throws {
    let one = try AIProvider.openai.request(for: .meal("x"), model: "m", key: secret)
    #expect(one == (try AIProvider.openai.request(for: .meal("x"), model: "m", key: secret)))
  }

  @Test func anEmptyModelOrBlankKeyIsRefused() {
    #expect(throws: RecipeAIError.invalidModel) {
      try AIProvider.openai.request(for: .meal("x"), model: "", key: secret)
    }
    #expect(throws: RecipeAIError.missingKey) {
      try AIProvider.openai.request(for: .meal("x"), model: "m", key: "")
    }
  }
}

@Suite("OpenAI responses")
struct OpenAIResponseTests {
  @Test func anExtractionAnswerIsReadWithItsUsage() throws {
    let text =
      #"{"recipe":"found","title":"Fried eggs","description":null,"servings":1,"prepMinutes":null,"cookMinutes":3,"totalMinutes":null,"ingredients":[{"line":"2 eggs","section":null,"unsure":false}],"steps":[{"text":"Fry them.","section":null,"unsure":false}],"tags":[],"notes":null,"unsure":[]}"#
    let answer = try AIProvider.openai.answer(status: 200, body: response(text: text))
    #expect(answer.inputTokens == 640 && answer.outputTokens == 97)
    let extraction = try answer.extraction(model: "gpt-6-luna")
    #expect(extraction.outcome == .found)
    #expect(extraction.recipe.title == "Fried eggs")
    #expect(extraction.recipe.ingredients.map(\.line) == ["2 eggs"])
    #expect(
      extraction.usage == AIUsage(model: "gpt-6-luna", inputTokens: 640, outputTokens: 97))
  }

  @Test func aMacrosAnswerSplitAcrossPartsIsJoined() throws {
    let body = response(parts: [
      ["type": "output_text", "text": #"{"servings":2,"calories":300,"#],
      ["type": "output_text", "text": #""protein":20,"carbs":10,"fat":15}"#],
    ])
    let answer = try AIProvider.openai.answer(status: 200, body: body)
    #expect(try answer.macros() == Macros(calories: 300, protein: 20, carbs: 10, fat: 15))
  }

  @Test func aMealAnswerIsRead() throws {
    let text =
      #"{"items":[{"name":"Eggs","amount":"2 large","food":true,"calories":143,"protein":12.5,"carbs":1,"fat":9.5}]}"#
    let items = try AIProvider.openai.answer(status: 200, body: response(text: text)).meal()
    #expect(
      items == [
        DescribedItem(
          name: "Eggs", amount: "2 large",
          macros: Macros(calories: 143, protein: 12.5, carbs: 1, fat: 9.5))
      ])
  }

  @Test func theMessageIsFoundAfterOtherItemsAndMissingUsageIsZero() throws {
    let body = json([
      "status": "completed",
      "output": [
        ["type": "reasoning", "summary": []],
        ["type": "message", "content": [["type": "output_text", "text": "{}"]]],
      ],
    ])
    let answer = try AIProvider.openai.answer(status: 200, body: body)
    #expect(answer.json == Data("{}".utf8))
    #expect(answer.inputTokens == 0 && answer.outputTokens == 0)
  }

  @Test func aRefusalIsAFailure() {
    let body = response(parts: [["type": "refusal", "refusal": "I can't help with that."]])
    #expect(throws: RecipeAIError.failed(detail: "refused")) {
      try AIProvider.openai.answer(status: 200, body: body)
    }
  }

  @Test func anIncompleteResponseIsAFailure() {
    let cut = response(
      parts: [["type": "output_text", "text": #"{"items":["#]], status: "incomplete",
      incomplete: "max_output_tokens")
    #expect(throws: RecipeAIError.failed(detail: "stopped: max_output_tokens")) {
      try AIProvider.openai.answer(status: 200, body: cut)
    }
    let failed = response(parts: [], status: "failed")
    #expect(throws: RecipeAIError.failed(detail: "stopped: failed")) {
      try AIProvider.openai.answer(status: 200, body: failed)
    }
  }

  @Test func anEmptyOrMissingAnswerIsAFailure() {
    #expect(throws: RecipeAIError.failed(detail: "empty answer")) {
      try AIProvider.openai.answer(status: 200, body: response(text: ""))
    }
    #expect(throws: RecipeAIError.failed(detail: "empty answer")) {
      try AIProvider.openai.answer(status: 200, body: response(parts: []))
    }
    let noMessage = json(["status": "completed", "output": [["type": "reasoning"]]])
    #expect(throws: RecipeAIError.failed(detail: "no answer")) {
      try AIProvider.openai.answer(status: 200, body: noMessage)
    }
    #expect(throws: RecipeAIError.failed(detail: "unreadable response")) {
      try AIProvider.openai.answer(status: 200, body: Data("<html>".utf8))
    }
  }

  @Test func outputThatIsntTheShapeAskedForIsAFailure() throws {
    let wrong = try AIProvider.openai.answer(
      status: 200, body: response(text: #"{"hello":"world"}"#))
    #expect(throws: RecipeAIError.failed(detail: "bad output")) { try wrong.extraction(model: "m") }
    let prose = try AIProvider.openai.answer(status: 200, body: response(text: "Here you go!"))
    #expect(throws: RecipeAIError.failed(detail: "bad output")) { try prose.meal() }
  }

  @Test func aRefusedKeyIsAnInvalidKey() {
    for status in [401, 403] {
      let body = failure(type: "invalid_request_error", code: "invalid_api_key")
      #expect(throws: RecipeAIError.invalidKey) {
        try AIProvider.openai.answer(status: status, body: body)
      }
    }
    #expect(throws: RecipeAIError.invalidKey) {
      try AIProvider.openai.answer(status: 401, body: Data())
    }
  }

  @Test func aSpentQuotaOrRateLimitIsRateLimited() {
    let quota = failure(type: "insufficient_quota", code: "insufficient_quota")
    #expect(throws: RecipeAIError.rateLimited) {
      try AIProvider.openai.answer(status: 429, body: quota)
    }
    #expect(throws: RecipeAIError.rateLimited) {
      try AIProvider.openai.answer(status: 429, body: Data())
    }
  }

  @Test func anUnknownModelIsItsOwnProblem() {
    let body = failure(type: "invalid_request_error", code: "model_not_found")
    #expect(throws: RecipeAIError.invalidModel) {
      try AIProvider.openai.answer(status: 404, body: body)
    }
  }

  @Test func timeoutsAndServerErrorsAreUnreachable() {
    for status in [408, 0, 500, 502, 503, 529] {
      #expect(throws: RecipeAIError.unreachable) {
        try AIProvider.openai.answer(status: status, body: Data())
      }
    }
  }

  @Test func otherRejectionsAreFailuresNamedByCodeOrTypeNeverByMessage() {
    let withCode = failure(
      type: "invalid_request_error", code: "unsupported_parameter",
      message: "Unsupported parameter near \(secret)")
    #expect(throws: RecipeAIError.failed(detail: "rejected: unsupported_parameter")) {
      try AIProvider.openai.answer(status: 400, body: withCode)
    }
    let typeOnly = failure(type: "invalid_request_error")
    #expect(throws: RecipeAIError.failed(detail: "rejected: invalid_request_error")) {
      try AIProvider.openai.answer(status: 422, body: typeOnly)
    }
    #expect(throws: RecipeAIError.failed(detail: "status 418")) {
      try AIProvider.openai.answer(status: 418, body: Data())
    }
  }

  @Test func theKeyIsInNoError() {
    let message = "Incorrect API key provided: \(secret)."
    let bodies = [
      failure(type: "invalid_request_error", code: "invalid_api_key", message: message),
      failure(type: "x", message: message), Data(message.utf8),
    ]
    for status in [400, 401, 404, 418, 429, 500] {
      for body in bodies {
        do throws(RecipeAIError) {
          _ = try AIProvider.openai.answer(status: status, body: body)
          Issue.record("\(status) should have thrown")
        } catch {
          #expect(!"\(error)".contains(secret))
          #expect(!error.localizedDescription.contains(secret))
        }
      }
    }
  }
}
