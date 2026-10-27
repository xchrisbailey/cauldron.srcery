import CauldronKit
import Foundation
import Testing

/// A long search that lacks one word still finds a recipe, under Close matches and after every
/// exact and typo match; a short one stays strict. Filler words such as "something" don't
/// count as words at all.
@Suite("Recipe search partial matches")
struct RecipeSearchPartialTests {
  private typealias Reason = RecipeSearchIndex.Reason

  private func results(_ text: String, in box: [RecipeSearchIndex.Entry] = SearchTestBox.corpus)
    -> [RecipeSearchIndex.Result]
  {
    RecipeSearchIndex(box).search(text)
  }

  // MARK: Filler words

  @Test func fillerWordsAreIgnored() {
    let plain = SearchTestBox.titles("chicken thighs")
    #expect(!plain.isEmpty)
    for filler in ["something", "thing", "recipe", "dish"] {
      #expect(SearchTestBox.titles("\(filler) chicken thighs") == plain)
      #expect(SearchTestBox.titles("chicken \(filler) thighs") == plain)
    }
  }

  @Test func fillerWordsDoNotCountTowardsTheThreeWordsPartialNeeds() {
    // Two meaningful words, so every one must match: Pad thai has no "spicy".
    #expect(SearchTestBox.titles("something spicy peanut").isEmpty)
    #expect(SearchTestBox.titles("recipe dish spicy peanut").isEmpty)
    // Three meaningful words behind the same filler find Pad thai as a partial match.
    #expect(SearchTestBox.titles("something spicy peanut noodles") == ["Pad thai"])
  }

  @Test func aSearchOfOnlyFillerWordsFindsNothing() {
    #expect(SearchTestBox.titles("something").isEmpty)
    #expect(SearchTestBox.titles("a dish or recipe").isEmpty)
  }

  // MARK: Partial matching

  @Test func threeWordsWithOneMissingFindTheRecipeAsAPartialMatch() {
    let found = results("eggs tomato chicken")
    #expect(found.map { SearchTestBox.title(of: $0.id) } == ["Shakshuka with feta"])
    #expect(found.first?.tier == .partial)
    #expect(found.first?.reason == Reason(matched: ["eggs", "tomato"], missing: "chicken"))
    #expect(found.first?.reason.line?.text == "Matched eggs, tomato · no chicken")
  }

  @Test func theMissingWordCanBeAnyOfTheWords() {
    for (text, missing) in [
      ("chicken eggs tomato", "chicken"), ("eggs chicken tomato", "chicken"),
      ("eggs tomato chicken", "chicken"),
    ] {
      let found = results(text)
      #expect(found.map { SearchTestBox.title(of: $0.id) } == ["Shakshuka with feta"])
      #expect(found.first?.reason.missing == missing)
    }
  }

  @Test func moreThanThreeWordsAlsoAllowOneMissing() {
    let found = results("eggs tomato feta chicken")
    #expect(found.map { SearchTestBox.title(of: $0.id) } == ["Shakshuka with feta"])
    #expect(found.first?.reason == Reason(matched: ["eggs", "tomato", "feta"], missing: "chicken"))
  }

  @Test func twoMissingWordsAreTooMany() {
    // Weeknight chicken has chicken and lemon; Shakshuka has eggs and tomato; none has three.
    #expect(results("eggs tomato chicken lemon").isEmpty)
  }

  @Test func oneOrTwoWordsMustAllMatch() {
    #expect(results("eggs chicken").isEmpty)
    #expect(results("chicken").count == 2)
    #expect(results("tomato eggs").map(\.tier) == [.exact])
    #expect(results("eggs pizza").isEmpty)
  }

  @Test func aSearchThatMatchesEveryWordHasNoMissingWord() {
    let found = results("eggs tomato feta")
    #expect(found.first?.tier == .exact)
    #expect(found.allSatisfy { $0.reason.missing == nil || $0.tier == .partial })
  }

  @Test func aTypoAndAMissingWordAreBothReported() {
    let found = results("eggs tomatto chicken")
    #expect(found.map { SearchTestBox.title(of: $0.id) } == ["Shakshuka with feta"])
    #expect(found.first?.tier == .partial)
    #expect(
      found.first?.reason
        == Reason(
          matched: ["eggs", "tomato"],
          forgiven: [.init(typed: "tomatto", matched: "tomato", kind: .typo)],
          missing: "chicken"))
    #expect(found.first?.reason.line?.text == "Matched eggs, tomato · no chicken")
  }

  @Test func aMisspeltWordNothingIsNearIsTheMissingWord() {
    let found = results("eggs tomato chikcenzzz")
    #expect(found.first?.reason.missing == "chikcenzzz")
  }

  // MARK: Ranking

  @Test func partialMatchesComeAfterExactAndCloseOnes() {
    let box = [
      SearchTestBox.entry("Mochiken lemon garlic", id: 1),
      SearchTestBox.entry("Chicken lemon garlic roast", id: 2),
      SearchTestBox.entry("Chicken lemon soup", id: 3),
      SearchTestBox.entry("Garlic lemon bread", id: 4),
    ]
    let found = results("chiken lemon garlic", in: box)
    #expect(found.map(\.tier) == [.exact, .close, .partial, .partial])
    #expect(
      found.map { SearchTestBox.title(of: $0.id, in: box) } == [
        "Mochiken lemon garlic", "Chicken lemon garlic roast", "Garlic lemon bread",
        "Chicken lemon soup",
      ])
    #expect(found.last?.reason.missing == "garlic")
    #expect(found.dropLast().last?.reason.missing == "chiken")
  }

  @Test func partialMatchesWithFewerMistakesComeFirstThenByTitle() {
    let box = [
      SearchTestBox.entry("Zucchini lemon", items: ["chicken"], id: 1),
      SearchTestBox.entry("Aardvark lemon", items: ["chicken"], id: 2),
      SearchTestBox.entry("Bake lemon", items: ["chicken"], id: 3),
    ]
    let found = results("chiken lemon garlic", in: box)
    #expect(found.allSatisfy { $0.tier == .partial })
    #expect(
      found.map { SearchTestBox.title(of: $0.id, in: box) } == [
        "Aardvark lemon", "Bake lemon", "Zucchini lemon",
      ])
  }

  @Test func glutenFreeDessertDoesNotFindTheCookies() {
    for text in ["gluten-free dessert", "gluten free dessert", "Gluten-Free Dessert"] {
      let titles = SearchTestBox.titles(text)
      #expect(!titles.contains("Brown butter chocolate chip cookies"))
    }
    // It is three words ("gluten", "free", "dessert"), so the gluten-free chicken, which has two
    // of them, is the one partial match.
    let found = results("gluten-free dessert")
    #expect(
      found.map { SearchTestBox.title(of: $0.id) } == [
        "Weeknight chicken thighs with lemon and garlic"
      ])
    #expect(found.first?.tier == .partial)
    #expect(found.first?.reason.line?.text == "Matched gluten, free · no dessert")
    // A dessert tag and flour are not gluten-free: the cookies match one word of three.
    #expect(SearchTestBox.titles("gluten dessert").isEmpty)
    #expect(SearchTestBox.titles("dessert flour") == ["Brown butter chocolate chip cookies"])
  }

  // MARK: The test set's descriptions

  /// The words a keyword job would add to the recipe's document, stubbed until #254 lands.
  private static let keywords: [String: String] = [
    "Pad thai": "spicy noodle dish thai",
    "Kimchi fried rice": "korean leftover rice quick",
    "Overnight oats": "make ahead breakfast",
    "Weeknight chicken thighs with lemon and garlic": "one pan roasted easy dinner",
    "Guacamole": "quick dip party snack",
  ]

  private static var keyworded: [RecipeSearchIndex.Entry] {
    SearchTestBox.corpus.map { entry in
      guard let extra = keywords[entry.title] else { return entry }
      return RecipeSearchIndex.Entry(
        id: entry.id, title: entry.title, document: entry.document + " " + extra)
    }
  }

  private func firstTitle(_ text: String, keywords: Bool) -> String? {
    let box = keywords ? Self.keyworded : SearchTestBox.corpus
    return results(text, in: box).first.map { SearchTestBox.title(of: $0.id) }
  }

  @Test func descriptionsThatNeedNoKeywordsFindTheirRecipe() {
    #expect(SearchTestBox.titles("eggs in tomato sauce") == ["Shakshuka with feta"])
    #expect(SearchTestBox.titles("vegan soup") == ["Tomato and white bean soup"])
    #expect(results("eggs in tomato sauce").map(\.tier) == [.exact])
  }

  @Test func spicyPeanutNoodlesFindsPadThaiWithoutKeywordsAndWithThem() {
    let bare = results("spicy peanut noodles")
    #expect(bare.map { SearchTestBox.title(of: $0.id) } == ["Pad thai"])
    #expect(bare.first?.tier == .partial)
    #expect(bare.first?.reason.line?.text == "Matched peanut, noodles · no spicy")

    let kept = results("spicy peanut noodles", in: Self.keyworded)
    #expect(kept.map { SearchTestBox.title(of: $0.id) } == ["Pad thai"])
    #expect(kept.first?.tier == .exact)
  }

  @Test func descriptionsThatNeedKeywordsFindTheirRecipeWithThem() {
    #expect(firstTitle("something with leftover rice", keywords: true) == "Kimchi fried rice")
    #expect(firstTitle("make ahead breakfast", keywords: true) == "Overnight oats")
    #expect(
      firstTitle("one pan chicken dinner", keywords: true)
        == "Weeknight chicken thighs with lemon and garlic")
  }

  @Test func descriptionsThatNeedKeywordsFindNothingTheyWouldNotWithoutThem() {
    // Strict with two meaningful words, and two missing of the rest.
    #expect(results("something with leftover rice").isEmpty)
    #expect(results("make ahead breakfast").isEmpty)
    #expect(results("one pan chicken dinner").isEmpty)
  }

  @Test func aDipForChipsFindsGuacamoleAsAPartialMatchThatNamesTheChips() {
    let found = results("quick dip for chips", in: Self.keyworded)
    #expect(found.map { SearchTestBox.title(of: $0.id) } == ["Guacamole"])
    #expect(found.first?.tier == .partial)
    #expect(found.first?.reason == Reason(matched: ["quick", "dip"], missing: "chips"))
    #expect(found.first?.reason.shortLine?.text == "Matched quick, dip · no chips")
  }
}
