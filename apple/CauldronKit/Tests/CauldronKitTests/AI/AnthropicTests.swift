import CauldronKit
import Foundation
import Testing

// The response bodies here are written by hand from Anthropic's documented Messages API shapes.
// They have not been recorded from the live API.

private let secret = "sk-ant-test-secret-123"

private func object(_ data: Data) throws -> [String: Any] {
  try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func json(_ value: Any) -> Data {
  try! JSONSerialization.data(withJSONObject: value)
}

private func response(blocks: [[String: Any]], stop: String = "end_turn") -> Data {
  json([
    "id": "msg_123", "type": "message", "role": "assistant", "model": "claude-opus-5-5",
    "content": blocks, "stop_reason": stop, "stop_sequence": NSNull(),
    "usage": ["input_tokens": 701, "output_tokens": 88],
  ])
}

private func response(text: String, stop: String = "end_turn") -> Data {
  response(blocks: [["type": "text", "text": text]], stop: stop)
}

private func failure(type: String, message: String = "nope") -> Data {
  json(["type": "error", "error": ["type": type, "message": message]])
}

@Suite("Anthropic requests")
struct AnthropicRequestTests {
  @Test func theRequestGoesToAFixedURLWithTheKeyInItsHeaderOnly() throws {
    let request = try AIProvider.anthropic.request(
      for: .meal("eggs on toast"), model: "claude-test", key: secret)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(request.url.query == nil)
    #expect(
      request.headers == [
        "x-api-key": secret, "anthropic-version": "2023-06-01",
        "content-type": "application/json", "anthropic-beta": "server-side-fallback-2026-07-01",
      ])
    #expect(!request.url.absoluteString.contains(secret))
    #expect(!String(decoding: request.body, as: UTF8.self).contains(secret))
  }

  @Test func theBodyCarriesThePromptAStrictSchemaAndTheFallback() throws {
    let input = ExtractInput(text: "2 eggs. Fry them.", kind: .text)
    let request = try AIProvider.anthropic.request(
      for: .extract(input), model: "claude-test", key: secret)
    let body = try object(request.body)
    #expect(body["model"] as? String == "claude-test")
    #expect(body["max_tokens"] as? Int == 16000)
    #expect(body["system"] as? String == AIPrompts.extract(input).system)
    #expect(body["fallbacks"] as? String == "default")
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    #expect(messages[0]["role"] as? String == "user")
    #expect(messages[0]["content"] as? String == "2 eggs. Fry them.")
    // Claude Opus 5.5 rejects these, so none is sent.
    for rejected in ["thinking", "temperature", "top_p", "top_k"] {
      #expect(body[rejected] == nil, "\(rejected)")
    }
    #expect(
      Set(body.keys) == ["model", "max_tokens", "system", "messages", "output_config", "fallbacks"])

    let config = try #require(body["output_config"] as? [String: Any])
    #expect(config["effort"] as? String == "low")
    let format = try #require(config["format"] as? [String: Any])
    #expect(format["type"] as? String == "json_schema")
    let schema = try #require(format["schema"] as? [String: Any])
    #expect(schema["additionalProperties"] as? Bool == false)
    #expect((schema["required"] as? [String])?.count == 12)
    // The schema's own names are left as they are, not snake-cased with the request's keys.
    let properties = try #require(schema["properties"] as? [String: [String: Any]])
    #expect(properties["prepMinutes"]?["type"] as? [String] == ["number", "null"])
  }

  @Test func aRequestIsTheSameEveryTime() throws {
    let one = try AIProvider.anthropic.request(for: .meal("x"), model: "m", key: secret)
    #expect(one == (try AIProvider.anthropic.request(for: .meal("x"), model: "m", key: secret)))
  }

  @Test func anEmptyModelOrBlankKeyIsRefused() {
    #expect(throws: RecipeAIError.invalidModel) {
      try AIProvider.anthropic.request(for: .meal("x"), model: "", key: secret)
    }
    #expect(throws: RecipeAIError.missingKey) {
      try AIProvider.anthropic.request(for: .meal("x"), model: "m", key: "")
    }
  }
}

@Suite("Anthropic responses")
struct AnthropicResponseTests {
  @Test func anExtractionAnswerIsReadWithItsUsage() throws {
    let text =
      #"{"recipe":"found","title":"Fried eggs","description":null,"servings":1,"prepMinutes":null,"cookMinutes":3,"totalMinutes":null,"ingredients":[{"line":"2 eggs","section":null,"unsure":false}],"steps":[{"text":"Fry them.","section":null,"unsure":false}],"tags":[],"notes":null,"unsure":[]}"#
    let answer = try AIProvider.anthropic.answer(status: 200, body: response(text: text))
    #expect(answer.inputTokens == 701 && answer.outputTokens == 88)
    let extraction = try answer.extraction(model: "claude-opus-5-5")
    #expect(extraction.outcome == .found)
    #expect(extraction.recipe.title == "Fried eggs")
    #expect(
      extraction.usage == AIUsage(model: "claude-opus-5-5", inputTokens: 701, outputTokens: 88))
  }

  @Test func theAnswerIsEveryTextBlockNotJustTheFirstContentBlock() throws {
    let body = response(blocks: [
      ["type": "thinking", "thinking": "Let me work it out.", "signature": "abc"],
      ["type": "text", "text": #"{"servings":2,"calories":300,"#],
      ["type": "text", "text": #""protein":20,"carbs":10,"fat":15}"#],
    ])
    let answer = try AIProvider.anthropic.answer(status: 200, body: body)
    #expect(try answer.macros() == Macros(calories: 300, protein: 20, carbs: 10, fat: 15))
  }

  @Test func aMealAnswerIsReadAndMissingUsageIsZero() throws {
    let text =
      #"{"items":[{"name":"Eggs","amount":"2 large","food":true,"calories":143,"protein":12.5,"carbs":1,"fat":9.5}]}"#
    let body = json(["content": [["type": "text", "text": text]], "stop_reason": "end_turn"])
    let answer = try AIProvider.anthropic.answer(status: 200, body: body)
    #expect(answer.inputTokens == 0 && answer.outputTokens == 0)
    #expect(
      try answer.meal() == [
        DescribedItem(
          name: "Eggs", amount: "2 large",
          macros: Macros(calories: 143, protein: 12.5, carbs: 1, fat: 9.5))
      ])
  }

  @Test func aRefusalIsAFailureEvenWithTextInIt() {
    let body = response(text: "I can't help with that.", stop: "refusal")
    #expect(throws: RecipeAIError.failed(detail: "refused")) {
      try AIProvider.anthropic.answer(status: 200, body: body)
    }
  }

  @Test func anAnswerCutOffByTheTokenLimitIsAFailure() {
    let body = response(text: #"{"items":["#, stop: "max_tokens")
    #expect(throws: RecipeAIError.failed(detail: "too long")) {
      try AIProvider.anthropic.answer(status: 200, body: body)
    }
  }

  @Test func anEmptyOrUnreadableAnswerIsAFailure() {
    #expect(throws: RecipeAIError.failed(detail: "empty answer")) {
      try AIProvider.anthropic.answer(status: 200, body: response(text: ""))
    }
    #expect(throws: RecipeAIError.failed(detail: "empty answer")) {
      try AIProvider.anthropic.answer(status: 200, body: response(blocks: []))
    }
    let onlyThinking = response(blocks: [["type": "thinking", "thinking": "hm"]])
    #expect(throws: RecipeAIError.failed(detail: "empty answer")) {
      try AIProvider.anthropic.answer(status: 200, body: onlyThinking)
    }
    #expect(throws: RecipeAIError.failed(detail: "unreadable response")) {
      try AIProvider.anthropic.answer(status: 200, body: Data("<html>".utf8))
    }
  }

  @Test func outputThatIsntTheShapeAskedForIsAFailure() throws {
    let wrong = try AIProvider.anthropic.answer(
      status: 200, body: response(text: #"{"hello":"world"}"#))
    #expect(throws: RecipeAIError.failed(detail: "bad output")) { try wrong.extraction(model: "m") }
    let prose = try AIProvider.anthropic.answer(status: 200, body: response(text: "Here you go!"))
    #expect(throws: RecipeAIError.failed(detail: "bad output")) { try prose.meal() }
  }

  @Test func aRefusedKeyIsAnInvalidKey() {
    for status in [401, 403] {
      #expect(throws: RecipeAIError.invalidKey) {
        try AIProvider.anthropic.answer(status: status, body: failure(type: "authentication_error"))
      }
    }
  }

  @Test func aSpentBalanceOrRateLimitIsRateLimited() {
    #expect(throws: RecipeAIError.rateLimited) {
      try AIProvider.anthropic.answer(status: 402, body: failure(type: "billing_error"))
    }
    #expect(throws: RecipeAIError.rateLimited) {
      try AIProvider.anthropic.answer(status: 429, body: failure(type: "rate_limit_error"))
    }
    #expect(throws: RecipeAIError.rateLimited) {
      try AIProvider.anthropic.answer(status: 429, body: Data())
    }
  }

  @Test func anUnknownModelIsItsOwnProblem() {
    #expect(throws: RecipeAIError.invalidModel) {
      try AIProvider.anthropic.answer(status: 404, body: failure(type: "not_found_error"))
    }
  }

  @Test func overloadTimeoutsAndServerErrorsAreUnreachable() {
    #expect(throws: RecipeAIError.unreachable) {
      try AIProvider.anthropic.answer(status: 529, body: failure(type: "overloaded_error"))
    }
    for status in [408, 0, 500, 502, 503] {
      #expect(throws: RecipeAIError.unreachable) {
        try AIProvider.anthropic.answer(status: status, body: Data())
      }
    }
  }

  @Test func otherRejectionsAreFailuresNamedByTypeNeverByMessage() {
    let invalid = failure(type: "invalid_request_error", message: "bad near \(secret)")
    #expect(throws: RecipeAIError.failed(detail: "rejected: invalid_request_error")) {
      try AIProvider.anthropic.answer(status: 400, body: invalid)
    }
    #expect(throws: RecipeAIError.failed(detail: "rejected: request_too_large")) {
      try AIProvider.anthropic.answer(status: 413, body: failure(type: "request_too_large"))
    }
    #expect(throws: RecipeAIError.failed(detail: "status 418")) {
      try AIProvider.anthropic.answer(status: 418, body: Data())
    }
  }

  @Test func theKeyIsInNoError() {
    let message = "invalid x-api-key: \(secret)"
    let bodies = [failure(type: "authentication_error", message: message), Data(message.utf8)]
    for status in [400, 401, 404, 418, 429, 500, 529] {
      for body in bodies {
        do throws(RecipeAIError) {
          _ = try AIProvider.anthropic.answer(status: status, body: body)
          Issue.record("\(status) should have thrown")
        } catch {
          #expect(!"\(error)".contains(secret))
          #expect(!error.localizedDescription.contains(secret))
        }
      }
    }
  }
}
