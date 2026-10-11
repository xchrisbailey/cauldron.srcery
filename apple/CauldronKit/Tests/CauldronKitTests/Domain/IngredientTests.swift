import CauldronKit
import Foundation
import Testing

private func parsed(
  quantity: Quantity? = Quantity(min: 1, max: nil),
  unit: UnitCode? = .cup,
  alt: AltMeasure? = nil
) -> ParsedIngredient {
  ParsedIngredient(
    quantity: quantity, unit: unit, item: "milk", note: nil, optional: false, alt: alt,
    original: "1 cup milk")
}

/// Ported from the `schemas` block of `packages/shared/test/ingredients/units.test.ts`.
@Suite("Quantity validity")
struct QuantityTests {
  @Test func enforcesMaxAtLeastMin() {
    #expect(Quantity(min: 1, max: nil).isValid)
    #expect(Quantity(min: 1, max: 1).isValid)
    #expect(Quantity(min: 1, max: 2).isValid)
    #expect(!Quantity(min: 3, max: 2).isValid)
    #expect(!Quantity(min: -1, max: nil).isValid)
  }

  @Test func rejectsNonFiniteAmounts() {
    #expect(!Quantity(min: .infinity, max: nil).isValid)
    #expect(!Quantity(min: .nan, max: nil).isValid)
    #expect(!Quantity(min: 1, max: .infinity).isValid)
    #expect(Quantity(min: 0, max: nil).isValid)
  }

  @Test func parsedIngredientIsValidOnlyWithValidAmounts() {
    #expect(parsed().isValid)
    #expect(parsed(quantity: nil, unit: nil).isValid)
    #expect(!parsed(quantity: Quantity(min: -1, max: nil)).isValid)
    #expect(!parsed(quantity: Quantity(min: .infinity, max: nil)).isValid)
    let alt = AltMeasure(quantity: Quantity(min: 190, max: nil), unit: .g)
    #expect(parsed(alt: alt).isValid)
    let badAlt = AltMeasure(quantity: Quantity(min: 2, max: 1), unit: .g)
    #expect(!parsed(alt: badAlt).isValid)
  }
}

@Suite("Ingredient JSON")
struct IngredientJSONTests {
  @Test func decodesTheTypeScriptShape() throws {
    let json = Data(
      """
      {"quantity":{"min":1.5,"max":null},"unit":"cup","item":"flour","note":"sifted",
       "optional":false,"alt":{"quantity":{"min":190,"max":null},"unit":"g"},
       "original":"1 1/2 cups (190g) flour, sifted"}
      """.utf8)
    let ingredient = try JSONDecoder().decode(ParsedIngredient.self, from: json)
    #expect(ingredient.quantity == Quantity(min: 1.5, max: nil))
    #expect(ingredient.unit == .cup)
    #expect(ingredient.alt == AltMeasure(quantity: Quantity(min: 190, max: nil), unit: .g))
    #expect(ingredient.note == "sifted")
    let again = try JSONDecoder().decode(
      ParsedIngredient.self, from: JSONEncoder().encode(ingredient))
    #expect(again == ingredient)
  }

  @Test func refusesAnUnknownUnit() {
    let json = Data(
      #"{"quantity":null,"unit":"furlong","item":"x","note":null,"optional":false,"alt":null,"original":"x"}"#
        .utf8)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ParsedIngredient.self, from: json)
    }
  }

  @Test func recipeIngredientAddsSectionAndMergeKey() throws {
    let json = Data(
      """
      {"section":"For the sauce","quantity":null,"unit":null,"item":"salt","note":null,
       "optional":true,"alt":null,"original":"salt, to taste","itemKey":"salt"}
      """.utf8)
    let ingredient = try JSONDecoder().decode(Ingredient.self, from: json)
    #expect(ingredient.section == "For the sauce")
    #expect(ingredient.itemKey == "salt")
    #expect(ingredient.optional)
  }
}
