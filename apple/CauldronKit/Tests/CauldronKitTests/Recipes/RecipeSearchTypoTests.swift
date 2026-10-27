import CauldronKit
import Foundation
import Testing

/// Typos find recipes. The cases come from the test set of "Write a test set of searches with
/// mistakes" (#245), over the sample recipes and the ones a box will plausibly hold.
@Suite("Recipe search typos")
struct RecipeSearchTypoTests {
  struct Typed: Sendable, CustomTestStringConvertible {
    let text: String
    let finds: Set<String>
    var testDescription: String { text }
  }

  static let chicken = "Weeknight chicken thighs with lemon and garlic"

  static let corpus: [Typed] = [
    Typed(text: "chiken", finds: [chicken, "Chicken tikka masala"]),
    Typed(text: "chikcen", finds: [chicken, "Chicken tikka masala"]),
    Typed(text: "shakshouka", finds: ["Shakshuka with feta"]),
    Typed(text: "shaksuka", finds: ["Shakshuka with feta"]),
    Typed(text: "choclate chip", finds: ["Brown butter chocolate chip cookies"]),
    Typed(text: "cannelini", finds: ["Tomato and white bean soup"]),
    Typed(text: "tikka massala", finds: ["Chicken tikka masala"]),
    Typed(text: "guacomole", finds: ["Guacamole"]),
    Typed(text: "avacado", finds: ["Guacamole"]),
    Typed(text: "parmigiana", finds: ["Aubergine parmigiana"]),
    Typed(text: "parmigiano", finds: ["Aubergine parmigiana"]),
    Typed(text: "parmesan", finds: ["Aubergine parmigiana"]),
    Typed(text: "jalapeno", finds: ["Guacamole"]),
  ]

  /// Searches that must find nothing: a correctly spelt word never pulls in a near miss, and a
  /// short word is never forgiven.
  static let nothing = [
    "bocoli", "pear", "beef", "mint", "salmon", "garbanzo", "gluten-free dessert", "chiken salmon",
    "rcie", "pasd thai", "xhicken", "shicken",
  ]

  @Test(arguments: corpus)
  func aMisspeltSearchFindsTheRecipe(_ typed: Typed) {
    #expect(Set(SearchTestBox.titles(typed.text)) == typed.finds)
  }

  @Test(arguments: nothing)
  func aSearchThatMatchesNothingFindsNothing(_ text: String) {
    #expect(SearchTestBox.titles(text).isEmpty)
  }

  @Test func riceFindsTheRiceRecipesAndNoOthers() {
    #expect(Set(SearchTestBox.titles("rice")) == ["Kimchi fried rice", "Pad thai"])
  }

  // MARK: Length

  /// A box of one recipe holding `word`, and the titles `typed` finds in it.
  private func finds(_ typed: String, in word: String) -> Bool {
    let box = [SearchTestBox.entry("Dish", items: [word], id: 1)]
    return !SearchTestBox.titles(typed, in: box).isEmpty
  }

  @Test func wordsOfFourLettersOrFewerMustMatchExactly() {
    #expect(finds("rice", in: "rice"))
    #expect(!finds("rise", in: "rice"))
    #expect(!finds("rcie", in: "rice"))
    #expect(!finds("ric", in: "rise"))
  }

  @Test func oneMistakeIsForgivenFromFiveLetters() {
    #expect(finds("breed", in: "bread"))
    #expect(!finds("bred", in: "bread"))
    #expect(finds("breadd", in: "bread"))
    #expect(!finds("bxxad", in: "bread"))
  }

  @Test func twoMistakesAreForgivenFromNineLetters() {
    // Eight letters, two mistakes: not forgiven. Nine letters, two mistakes: forgiven.
    #expect(!finds("chacalat", in: "chocolate"))
    #expect(finds("chocalat", in: "chocolate"))
    #expect(finds("chacalate", in: "chocolate"))
    #expect(!finds("chacalatx", in: "chocolate"))
  }

  @Test func theAllowanceFollowsTheLengthOfTheTypedWord() {
    // Typed "brocoli" is seven letters: one mistake is forgiven, two are not.
    #expect(finds("brocoli", in: "broccoli"))
    #expect(!finds("brocolx", in: "broccoli"))
    // Typed "tumeric" is seven letters, and "turmeric" is one letter longer.
    #expect(finds("tumeric", in: "turmeric"))
    // Typed "zuchini" is seven letters: one mistake.
    #expect(finds("zuchini", in: "zucchini"))
  }

  // MARK: Swap

  @Test func aSwapOfTwoNeighbouringLettersIsOneMistake() {
    #expect(finds("braed", in: "bread"))
    #expect(finds("chikcen", in: "chicken"))
    // Two separate substitutions are two mistakes, so five letters do not forgive them.
    #expect(!finds("brxxd", in: "bread"))
    // Letters that are not neighbours are two substitutions.
    #expect(!finds("daerb", in: "bread"))
  }

  @Test func aSwapAtTheStartIsStillAWrongFirstLetter() {
    #expect(!finds("rbead", in: "bread"))
  }

  // MARK: First letter

  @Test func theFirstLetterMustBeRight() {
    #expect(finds("chiken", in: "chicken"))
    #expect(!finds("shicken", in: "chicken"))
    #expect(!finds("hicken", in: "chicken"))
    #expect(!finds("xchicken", in: "chicken"))
  }

  // MARK: Digits

  @Test func numbersAndMixedWordsAreNeverForgiven() {
    let box = [SearchTestBox.entry("Dish", items: ["250g flour", "100g sugar"], id: 1)]
    #expect(SearchTestBox.titles("250g", in: box) == ["Dish"])
    #expect(SearchTestBox.titles("200g", in: box).isEmpty)
    #expect(SearchTestBox.titles("251", in: box).isEmpty)
    #expect(SearchTestBox.titles("1000", in: box).isEmpty)
    #expect(SearchTestBox.titles("25og", in: box).isEmpty)
    #expect(SearchTestBox.titles("flour 200", in: box).isEmpty)
  }

  // MARK: Fall back only on a miss

  @Test func aWordThatMatchesExactlyNeverPullsInNearMisses() {
    let box = [
      SearchTestBox.entry("Pastry case", id: 1),
      SearchTestBox.entry("Pasta bake", id: 2),
    ]
    // "pastr" is one letter from "pasta", but it starts "pastry" exactly.
    #expect(SearchTestBox.titles("pastr", in: box) == ["Pastry case"])
    // "pastx" starts nothing, so it falls back, and both are one mistake away.
    #expect(Set(SearchTestBox.titles("pastx", in: box)) == ["Pastry case", "Pasta bake"])
  }

  @Test func beetNeverBringsUpBeefAndBeefNeverBringsUpBeet() {
    let box = [
      SearchTestBox.entry("Beef stew", id: 1),
      SearchTestBox.entry("Beet salad", id: 2),
    ]
    #expect(SearchTestBox.titles("beet", in: box) == ["Beet salad"])
    #expect(SearchTestBox.titles("beef", in: box) == ["Beef stew"])
    let onlyBeef = [SearchTestBox.entry("Beef stew", id: 1)]
    #expect(SearchTestBox.titles("beet", in: onlyBeef).isEmpty)
  }

  @Test func eachWordIsJudgedOnItsOwn() {
    // "chip" matches as it is; "choclate" has no exact match and is forgiven.
    #expect(
      SearchTestBox.titles("choclate chip") == ["Brown butter chocolate chip cookies"])
    // The forgiven word still has to be in the recipe.
    #expect(SearchTestBox.titles("choclate feta").isEmpty)
  }

  // MARK: Accents

  @Test func accentsFoldBothWays() {
    #expect(SearchTestBox.titles("jalapeno") == ["Guacamole"])
    #expect(SearchTestBox.titles("jalapeño") == ["Guacamole"])
    let box = [
      SearchTestBox.entry("Crème brûlée", id: 1),
      SearchTestBox.entry("Creme caramel", id: 2),
    ]
    #expect(Set(SearchTestBox.titles("creme", in: box)) == ["Crème brûlée", "Creme caramel"])
    #expect(Set(SearchTestBox.titles("crème", in: box)) == ["Crème brûlée", "Creme caramel"])
    #expect(SearchTestBox.titles("brulee", in: box) == ["Crème brûlée"])
    #expect(SearchTestBox.titles("crème brûlée", in: box) == ["Crème brûlée"])
  }

  @Test func foldingIsNotATypo() {
    let index = RecipeSearchIndex(SearchTestBox.corpus)
    #expect(index.search("jalapeno").map(\.tier) == [.exact])
    #expect(index.search("jalapeño").map(\.tier) == [.exact])
  }

  @Test func aMisspeltAccentedWordIsForgivenAfterFolding() {
    let box = [SearchTestBox.entry("Jalapeño poppers", id: 1)]
    #expect(SearchTestBox.titles("jalapenio", in: box) == ["Jalapeño poppers"])
  }
}
