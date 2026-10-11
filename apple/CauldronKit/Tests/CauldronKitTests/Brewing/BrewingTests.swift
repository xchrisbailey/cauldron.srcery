import CauldronKit
import Testing

/// Ingredients with only the key filled in, which is all `stepIngredients` reads.
func brewingIngredients(_ items: String...) -> [Ingredient] {
  brewingIngredients(items)
}

func brewingIngredients(_ items: [String]) -> [Ingredient] {
  brewingIngredients(keys: items.map(ingredientKey))
}

/// Ingredients with the item keys exactly as given.
func brewingIngredients(keys: [String]) -> [Ingredient] {
  keys.map {
    Ingredient(
      section: nil, quantity: nil, unit: nil, item: $0, note: nil, optional: false, alt: nil,
      original: $0, itemKey: $0)
  }
}

func brewingSteps(_ texts: String...) -> [Step] {
  texts.map { Step(section: nil, text: $0, timerSeconds: nil) }
}

/// Ported from `packages/shared/test/brewing.test.ts`.
@Suite("stepIngredients")
struct StepIngredientsTests {
  @Test func findsIngredientsNamedInFullPluralOrSingular() {
    let list = brewingIngredients("olive oil", "onions", "garlic", "chili flakes")
    let steps = brewingSteps(
      "Warm the olive oil and soften the onion.",
      "Stir in the garlic and chili flake.",
      "Serve.")
    #expect(stepIngredients(steps, list) == [[0, 1], [2, 3], []])
  }

  @Test func matchesTheLastWordOfALongerItem() {
    let list = brewingIngredients("red bell pepper", "crushed tomatoes")
    let steps = brewingSteps("Add the pepper, then the tomatoes.")
    #expect(stepIngredients(steps, list) == [[0, 1]])
  }

  @Test func prefersAnItemNamedInFullOverOthersThatShareItsLastWord() {
    let list = brewingIngredients("red bell pepper", "black pepper")
    #expect(stepIngredients(brewingSteps("Season with black pepper."), list) == [[1]])
  }

  @Test func doesNotMatchVagueLastWordsOnTheirOwn() {
    let list = brewingIngredients("lemon juice", "chicken stock")
    #expect(stepIngredients(brewingSteps("Add the juice and the stock."), list) == [[]])
    #expect(
      stepIngredients(brewingSteps("Add the lemon juice and the chicken stock."), list) == [[0, 1]])
  }

  @Test func ignoresCaseAndPunctuation() {
    let list = brewingIngredients("Eggs")
    #expect(stepIngredients(brewingSteps("Crack in the EGGS!"), list) == [[0]])
  }
}

@Suite("stepIngredients with names inside other names")
struct NamesInsideOtherNamesTests {
  @Test(
    arguments: [
      (["onions", "green onions"], "Scatter over the green onions.", [1]),
      (["butter", "peanut butter"], "Stir in the peanut butter.", [1]),
      (["tomatoes", "tomato paste"], "Add the tomato paste.", [1]),
      (["salt", "kosher salt"], "Season with kosher salt.", [1]),
      (["onions", "green onions"], "Fry the onions, then add the green onions.", [0, 1]),
    ])
  func longerNameClaimsItsWords(items: [String], text: String, expected: [Int]) {
    #expect(stepIngredients(brewingSteps(text), brewingIngredients(items)) == [expected])
  }
}
