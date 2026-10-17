import CauldronKit
import Testing

/// Ported from `packages/shared/test/ingredients/key.test.ts`.
@Suite("ingredientKey")
struct KeyTests {
  @Test(
    arguments: [
      ("Eggs", "egg"),
      ("large eggs", "egg"),
      ("  Large   Eggs ", "egg"),
      ("medium onions", "onion"),
      ("small red onion", "red onion"),
      ("tomatoes", "tomato"),
      ("potatoes", "potato"),
      ("cherries", "cherry"),
      ("berries", "berry"),
      ("peaches", "peach"),
      ("radishes", "radish"),
      ("cloves", "clove"),
      ("olives", "olive"),
      ("bay leaves", "bay leaf"),
      ("chickpeas", "chickpea"),
      ("hummus", "hummus"),
      ("asparagus", "asparagus"),
      ("couscous", "couscous"),
      ("molasses", "molasses"),
      ("olive oil", "olive oil"),
      ("Olive Oil", "olive oil"),
      ("green onions", "green onion"),
      ("extra large egg yolks", "egg yolk"),
      ("", ""),
    ])
  func keys(input: String, expected: String) {
    #expect(ingredientKey(input) == expected)
  }

  @Test func isIdempotent() {
    for s in ["Large Eggs", "tomatoes", "bay leaves", "cherries"] {
      #expect(ingredientKey(ingredientKey(s)) == ingredientKey(s))
    }
  }

  // Extra cases that pin edges of the reference down (checked against the TypeScript).

  @Test func singularizesOneWord() {
    #expect(singularize("eggs") == "egg")
    #expect(singularize("leaves") == "leaf")
    #expect(singularize("glass") == "glass")
    #expect(singularize("gas") == "gas")
    #expect(singularize("tomatoes") == "tomato")
    #expect(singularize("boxes") == "box")
    #expect(singularize("cherries") == "cherry")
    #expect(singularize("pies") == "pie")
    #expect(singularize("is") == "is")
  }

  @Test func fallsBackToTheTrimmedLowercaseTextWhenNothingIsAWord() {
    #expect(ingredientKey("  ½ !!  ") == "½ !!")
    #expect(ingredientKey("Ñ") == "ñ")
    #expect(ingredientKey("ΟΔΟΣ") == "οδος")
  }

  @Test func readsAWordNamedLikeAnObjectMethodAsAWord() {
    // The TypeScript looked "constructor" up on a plain object and answered with a function.
    #expect(ingredientKey("constructor") == "constructor")
  }
}
