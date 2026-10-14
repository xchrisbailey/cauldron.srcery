import CauldronKit
import Foundation
import Testing

/// The strict JSON Schema that OpenAI and Anthropic take, rendered from the same definition as
/// Gemini's `responseSchema`.
@Suite("Strict JSON Schema")
struct AISchemaTests {
  private func render(_ schema: AISchema) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(schema.strictJSONSchema)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func text(_ schema: AISchema) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(schema.strictJSONSchema), as: UTF8.self)
  }

  @Test func anObjectIsClosedAndEveryPropertyIsRequired() throws {
    let schema = try render(
      .object([("a", .string()), ("b", .number(nullable: true)), ("c", .boolean())]))
    #expect(schema["type"] as? String == "object")
    #expect(schema["additionalProperties"] as? Bool == false)
    #expect(schema["required"] as? [String] == ["a", "b", "c"])
    #expect(schema["propertyOrdering"] == nil)
  }

  @Test func aNullableFieldIsATypeArrayAndOtherFieldsAreASingleType() throws {
    let properties = try #require(
      try render(
        .object([
          ("s", .string()), ("sn", .string(nullable: true)), ("n", .number()),
          ("nn", .number(nullable: true)), ("b", .boolean()),
        ]))["properties"] as? [String: [String: Any]])
    #expect(properties["s"]?["type"] as? String == "string")
    #expect(properties["sn"]?["type"] as? [String] == ["string", "null"])
    #expect(properties["n"]?["type"] as? String == "number")
    #expect(properties["nn"]?["type"] as? [String] == ["number", "null"])
    #expect(properties["b"]?["type"] as? String == "boolean")
    #expect(properties["s"]?["nullable"] == nil)
  }

  @Test func enumsArraysAndDescriptionsAreKept() throws {
    let properties = try #require(
      try render(
        .object([
          ("kind", .string(description: "Which.", values: ["a", "b"])),
          ("maybe", .string(nullable: true, values: ["a"])),
          ("list", .array(of: .string(), description: "Several.")),
        ]))["properties"] as? [String: [String: Any]])
    #expect(properties["kind"]?["enum"] as? [String] == ["a", "b"])
    #expect(properties["kind"]?["description"] as? String == "Which.")
    // A field that may be null may answer null from its enum, too.
    let maybe = try #require(properties["maybe"]?["enum"] as? [Any])
    #expect(maybe.count == 2 && maybe[0] as? String == "a" && maybe[1] is NSNull)
    #expect(properties["list"]?["type"] as? String == "array")
    #expect(properties["list"]?["description"] as? String == "Several.")
    #expect((properties["list"]?["items"] as? [String: Any])?["type"] as? String == "string")
  }

  @Test func nestedObjectsAreClosedToo() throws {
    let recipe = try render(AITask.extract(ExtractInput(text: "x", kind: .text)).schema)
    let properties = try #require(recipe["properties"] as? [String: [String: Any]])
    for name in ["ingredients", "steps"] {
      let items = try #require(properties[name]?["items"] as? [String: Any])
      #expect(items["additionalProperties"] as? Bool == false, "\(name)")
      #expect((items["required"] as? [String])?.count == 3, "\(name)")
    }
    let meal = try render(AITask.meal("x").schema)
    let items = try #require(
      (meal["properties"] as? [String: [String: Any]])?["items"]?["items"] as? [String: Any])
    #expect(items["additionalProperties"] as? Bool == false)
    #expect(
      items["required"] as? [String]
        == ["name", "amount", "food", "calories", "protein", "carbs", "fat"])
  }

  @Test func theRecipeSchemaIsRenderedInFull() throws {
    #expect(
      try text(AITask.extract(ExtractInput(text: "x", kind: .text)).schema)
        == #"{"additionalProperties":false,"properties":{"cookMinutes":{"description":"Whole minutes, or null.","type":["number","null"]},"description":{"description":"One or two sentences about the dish from the text, or null. Never invent one.","type":["string","null"]},"ingredients":{"items":{"additionalProperties":false,"properties":{"line":{"description":"The ingredient line exactly as written, quantity and unit included.","type":"string"},"section":{"description":"The heading it sits under, like \"For the sauce\", or null.","type":["string","null"]},"unsure":{"description":"True when you had to guess at this line or it may be misread.","type":"boolean"}},"required":["line","section","unsure"],"type":"object"},"type":"array"},"notes":{"description":"Tips, storage or substitutions from the text, or null.","type":["string","null"]},"prepMinutes":{"description":"Whole minutes, or null.","type":["number","null"]},"recipe":{"description":"\"found\" when the text has a recipe (ingredients and method). \"inVideo\" when it only points to a recipe shown or spoken in a video. \"missing\" otherwise.","enum":["found","missing","inVideo"],"type":"string"},"servings":{"type":["number","null"]},"steps":{"items":{"additionalProperties":false,"properties":{"section":{"type":["string","null"]},"text":{"description":"One step of the method, as written.","type":"string"},"unsure":{"type":"boolean"}},"required":["text","section","unsure"],"type":"object"},"type":"array"},"tags":{"description":"Up to five short tags already implied by the text, like a cuisine or a diet.","items":{"type":"string"},"type":"array"},"title":{"type":["string","null"]},"totalMinutes":{"description":"Whole minutes, or null.","type":["number","null"]},"unsure":{"description":"Top-level fields you guessed or aren't sure of.","items":{"enum":["title","description","servings","prepMinutes","cookMinutes","totalMinutes","macros","sourceUrl","tags","notes"],"type":"string"},"type":"array"}},"required":["recipe","title","description","servings","prepMinutes","cookMinutes","totalMinutes","ingredients","steps","tags","notes","unsure"],"type":"object"}"#
    )
  }

  @Test func theMacrosSchemaIsRenderedInFull() throws {
    #expect(
      try text(AITask.macros(MacroEstimateInput(title: nil, servings: nil, ingredients: [])).schema)
        == #"{"additionalProperties":false,"properties":{"calories":{"description":"Kilocalories per serving.","type":["number","null"]},"carbs":{"description":"Grams of carbohydrate per serving.","type":["number","null"]},"fat":{"description":"Grams of fat per serving.","type":["number","null"]},"protein":{"description":"Grams of protein per serving.","type":["number","null"]},"servings":{"description":"The servings you divided by: the given yield, or your own guess when none was given.","type":["number","null"]}},"required":["servings","calories","protein","carbs","fat"],"type":"object"}"#
    )
  }

  @Test func theMealSchemaIsRenderedInFull() throws {
    #expect(
      try text(AITask.meal("x").schema)
        == #"{"additionalProperties":false,"properties":{"items":{"items":{"additionalProperties":false,"properties":{"amount":{"description":"How much, as the cook said it or a typical portion: \"2 large\", \"1 slice\". Null if unknown.","type":["string","null"]},"calories":{"description":"Kilocalories for that amount.","type":["number","null"]},"carbs":{"description":"Grams of carbohydrate for that amount.","type":["number","null"]},"fat":{"description":"Grams of fat for that amount.","type":["number","null"]},"food":{"description":"False when this isn't something eaten or drunk; its numbers must then be null.","type":"boolean"},"name":{"description":"The food, short and plain: \"Eggs\", \"Sourdough\".","type":"string"},"protein":{"description":"Grams of protein for that amount.","type":["number","null"]}},"required":["name","amount","food","calories","protein","carbs","fat"],"type":"object"},"type":"array"}},"required":["items"],"type":"object"}"#
    )
  }

  @Test func geminiKeepsItsOwnRendering() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(AISchema.object([("a", .string(nullable: true))]))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["type"] as? String == "OBJECT")
    #expect(json["propertyOrdering"] as? [String] == ["a"])
    #expect(json["additionalProperties"] == nil)
  }
}
