import CauldronKit
import Foundation
import Testing

// The response bodies here are written by hand from Gemini's documented REST shapes. They
// have not been recorded from the live API.

private func object(_ data: Data) throws -> [String: Any] {
  try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func response(text: String, finish: String = "STOP") -> Data {
  let body: [String: Any] = [
    "candidates": [
      ["content": ["role": "model", "parts": [["text": text]]], "finishReason": finish]
    ],
    "usageMetadata": [
      "promptTokenCount": 812, "candidatesTokenCount": 143, "totalTokenCount": 955,
    ],
    "modelVersion": "gemini-3.5-flash-lite",
  ]
  return try! JSONSerialization.data(withJSONObject: body)
}

@Suite("Gemini requests")
struct GeminiRequestTests {
  @Test func theEndpointNamesTheModelAndNeverCarriesTheKey() throws {
    let url = try #require(Gemini.endpoint(model: Gemini.defaultModel))
    #expect(
      url.absoluteString
        == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent"
    )
    #expect(url.query == nil)
    #expect(Gemini.keyHeader == "x-goog-api-key")
    #expect(Gemini.endpoint(model: "") == nil)
    #expect(Gemini.endpoint(model: "x/../y?key=1") == nil)
  }

  @Test func anExtractionRequestCarriesThePromptAndAsksForJSON() throws {
    let input = ExtractInput(text: "2 eggs. Fry them.", kind: .text)
    let body = try object(Gemini.requestBody(for: .extract(input)))

    let system = try #require(body["systemInstruction"] as? [String: Any])
    let systemParts = try #require(system["parts"] as? [[String: Any]])
    #expect(systemParts.first?["text"] as? String == AIPrompts.extract(input).system)
    #expect(system["role"] == nil)

    let contents = try #require(body["contents"] as? [[String: Any]])
    #expect(contents.count == 1)
    #expect(contents[0]["role"] as? String == "user")
    let parts = try #require(contents[0]["parts"] as? [[String: Any]])
    #expect(parts.first?["text"] as? String == "2 eggs. Fry them.")

    let config = try #require(body["generationConfig"] as? [String: Any])
    #expect(config["responseMimeType"] as? String == "application/json")
    let schema = try #require(config["responseSchema"] as? [String: Any])
    #expect(schema["type"] as? String == "OBJECT")
    let order = [
      "recipe", "title", "description", "servings", "prepMinutes", "cookMinutes", "totalMinutes",
      "ingredients", "steps", "tags", "notes", "unsure",
    ]
    #expect(schema["propertyOrdering"] as? [String] == order)
    #expect(schema["required"] as? [String] == order)

    let properties = try #require(schema["properties"] as? [String: [String: Any]])
    #expect(properties["recipe"]?["enum"] as? [String] == ["found", "missing", "inVideo"])
    #expect(properties["recipe"]?["nullable"] == nil)
    #expect(properties["title"]?["nullable"] as? Bool == true)
    #expect(properties["servings"]?["type"] as? String == "NUMBER")
    #expect(properties["prepMinutes"]?["description"] as? String == "Whole minutes, or null.")
    let line = try #require(properties["ingredients"]?["items"] as? [String: Any])
    #expect(line["propertyOrdering"] as? [String] == ["line", "section", "unsure"])
    let unsure = try #require(properties["unsure"]?["items"] as? [String: Any])
    #expect(
      unsure["enum"] as? [String] == [
        "title", "description", "servings", "prepMinutes", "cookMinutes", "totalMinutes", "macros",
        "sourceUrl", "tags", "notes",
      ])
  }

  @Test func theMacroAndMealRequestsUseTheirOwnPromptsAndShapes() throws {
    let macroInput = MacroEstimateInput(title: "Dal", servings: 4, ingredients: ["1 cup lentils"])
    let macros = try object(Gemini.requestBody(for: .macros(macroInput)))
    let macroSchema = try #require(
      (macros["generationConfig"] as? [String: Any])?["responseSchema"] as? [String: Any])
    #expect(
      macroSchema["propertyOrdering"] as? [String]
        == ["servings", "calories", "protein", "carbs", "fat"])
    let macroText = try #require(
      ((macros["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])?.first?[
        "text"]
        as? String)
    #expect(macroText == AIPrompts.macros(macroInput).user)

    let meal = try object(Gemini.requestBody(for: .meal("eggs on toast")))
    let mealSchema = try #require(
      (meal["generationConfig"] as? [String: Any])?["responseSchema"] as? [String: Any])
    let items = try #require(
      (mealSchema["properties"] as? [String: [String: Any]])?["items"]?["items"] as? [String: Any])
    #expect(
      items["propertyOrdering"] as? [String]
        == ["name", "amount", "food", "calories", "protein", "carbs", "fat"])
  }

  @Test func aRequestBodyIsTheSameEveryTime() throws {
    let task = Gemini.Task.meal("eggs on toast")
    #expect(try Gemini.requestBody(for: task) == Gemini.requestBody(for: task))
  }
}

@Suite("Gemini responses")
struct GeminiResponseTests {
  @Test func anExtractionAnswerIsReadWithItsUsage() throws {
    let json =
      #"{"recipe":"found","title":"Fried eggs","description":null,"servings":1,"prepMinutes":null,"cookMinutes":3,"totalMinutes":null,"ingredients":[{"line":"2 eggs","section":null,"unsure":false}],"steps":[{"text":"Fry them.","section":null,"unsure":false}],"tags":[],"notes":null,"unsure":[]}"#
    let answer = try Gemini.answer(status: 200, body: response(text: json))
    #expect(answer.inputTokens == 812)
    #expect(answer.outputTokens == 143)
    let extraction = try Gemini.extraction(from: answer, model: "gemini-3.5-flash-lite")
    #expect(extraction.outcome == .found)
    #expect(extraction.recipe.title == "Fried eggs")
    #expect(extraction.recipe.cookMinutes == 3)
    #expect(extraction.recipe.ingredients.map(\.line) == ["2 eggs"])
    #expect(
      extraction.usage
        == AIUsage(model: "gemini-3.5-flash-lite", inputTokens: 812, outputTokens: 143))
    #expect(!extraction.rough)
  }

  @Test func anAnswerSplitAcrossPartsIsJoined() throws {
    let body = try JSONSerialization.data(withJSONObject: [
      "candidates": [
        [
          "content": [
            "parts": [
              ["text": #"{"servings":2,"calories":300,"#],
              ["text": #""protein":20,"carbs":10,"fat":15}"#],
            ]
          ],
          "finishReason": "STOP",
        ]
      ]
    ])
    let answer = try Gemini.answer(status: 200, body: body)
    #expect(
      try Gemini.macros(from: answer) == Macros(calories: 300, protein: 20, carbs: 10, fat: 15))
    #expect(answer.inputTokens == 0 && answer.outputTokens == 0)
  }

  @Test func aMealAnswerIsRead() throws {
    let json =
      #"{"items":[{"name":"Eggs","amount":"2 large","food":true,"calories":143,"protein":12.5,"carbs":1,"fat":9.5}]}"#
    let items = try Gemini.meal(from: Gemini.answer(status: 200, body: response(text: json)))
    #expect(
      items == [
        DescribedItem(
          name: "Eggs", amount: "2 large",
          macros: Macros(calories: 143, protein: 12.5, carbs: 1, fat: 9.5))
      ])
  }

  @Test func outputThatIsntTheShapeAskedForIsAFailure() throws {
    let answer = try Gemini.answer(status: 200, body: response(text: #"{"hello":"world"}"#))
    #expect(throws: RecipeAIError.failed(detail: "bad output")) {
      try Gemini.extraction(from: answer, model: "m")
    }
    let prose = try Gemini.answer(status: 200, body: response(text: "Here is your recipe!"))
    #expect(throws: RecipeAIError.failed(detail: "bad output")) { try Gemini.meal(from: prose) }
  }

  @Test func aCutOffOrBlockedAnswerIsAFailure() throws {
    #expect(throws: RecipeAIError.failed(detail: "stopped: MAX_TOKENS")) {
      try Gemini.answer(status: 200, body: response(text: #"{"items":["#, finish: "MAX_TOKENS"))
    }
    let blocked = try JSONSerialization.data(withJSONObject: [
      "promptFeedback": ["blockReason": "SAFETY"]
    ])
    #expect(throws: RecipeAIError.failed(detail: "blocked: SAFETY")) {
      try Gemini.answer(status: 200, body: blocked)
    }
    #expect(throws: RecipeAIError.failed(detail: "no answer")) {
      try Gemini.answer(status: 200, body: Data("{}".utf8))
    }
    #expect(throws: RecipeAIError.failed(detail: "unreadable response")) {
      try Gemini.answer(status: 200, body: Data("<html>".utf8))
    }
    #expect(throws: RecipeAIError.failed(detail: "empty answer")) {
      try Gemini.answer(status: 200, body: response(text: ""))
    }
  }

  private func failure(_ code: Int, status: String, message: String, reason: String? = nil) -> Data
  {
    var error: [String: Any] = ["code": code, "message": message, "status": status]
    if let reason {
      error["details"] = [["@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": reason]]
    }
    return try! JSONSerialization.data(withJSONObject: ["error": error])
  }

  @Test func aSpentQuotaIsRateLimited() {
    let body = failure(
      429, status: "RESOURCE_EXHAUSTED", message: "You exceeded your current quota.")
    #expect(throws: RecipeAIError.rateLimited) { try Gemini.answer(status: 429, body: body) }
    // The status alone decides it, whatever the body holds.
    #expect(throws: RecipeAIError.rateLimited) { try Gemini.answer(status: 429, body: Data()) }
  }

  @Test func aRefusedKeyIsAnInvalidKey() {
    let bad = failure(
      400, status: "INVALID_ARGUMENT", message: "API key not valid. Please pass a valid API key.",
      reason: "API_KEY_INVALID")
    #expect(throws: RecipeAIError.invalidKey) { try Gemini.answer(status: 400, body: bad) }
    let denied = failure(403, status: "PERMISSION_DENIED", message: "Permission denied.")
    #expect(throws: RecipeAIError.invalidKey) { try Gemini.answer(status: 403, body: denied) }
    #expect(throws: RecipeAIError.invalidKey) { try Gemini.answer(status: 401, body: Data()) }
  }

  @Test func aServerErrorIsUnreachableAndABadRequestIsAFailure() {
    for status in [500, 503, 504] {
      #expect(throws: RecipeAIError.unreachable) { try Gemini.answer(status: status, body: Data()) }
    }
    let rejected = failure(400, status: "INVALID_ARGUMENT", message: "Invalid JSON payload.")
    #expect(throws: RecipeAIError.failed(detail: "rejected: INVALID_ARGUMENT")) {
      try Gemini.answer(status: 400, body: rejected)
    }
    #expect(throws: RecipeAIError.failed(detail: "status 404")) {
      try Gemini.answer(status: 404, body: Data())
    }
  }
}
