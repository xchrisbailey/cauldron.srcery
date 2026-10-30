import CauldronKit
import Foundation
import Testing

/// Results say why a recipe matched, and the reason turns into the one plain line a close match
/// shows. Synonyms and partial matches arrive in later tickets, so their reasons are built by
/// hand here and tested through the same formatter.
@Suite("Recipe search reasons")
struct RecipeSearchReasonTests {
  private typealias Reason = RecipeSearchIndex.Reason

  // MARK: What the index reports

  @Test func aTypoIsReportedAsForgivenAndMatchedToTheRecipesWord() {
    let index = RecipeSearchIndex(SearchTestBox.corpus)
    let results = index.search("chiken")
    #expect(results.count == 2)
    for result in results {
      #expect(result.tier == .close)
      #expect(
        result.reason
          == Reason(
            matched: ["chicken"],
            forgiven: [.init(typed: "chiken", matched: "chicken", kind: .typo)]))
    }
  }

  @Test func eachWordIsReportedAsItWasMatched() {
    let index = RecipeSearchIndex(SearchTestBox.corpus)
    let result = index.search("choclate chip").first
    #expect(result?.tier == .close)
    #expect(
      result?.reason
        == Reason(
          matched: ["chocolate", "chip"],
          forgiven: [.init(typed: "choclate", matched: "chocolate", kind: .typo)]))
  }

  @Test func anExactMatchHasNothingToExplain() {
    let index = RecipeSearchIndex(SearchTestBox.corpus)
    let results = index.search("chicken")
    #expect(!results.isEmpty)
    #expect(results.allSatisfy { $0.tier == .exact && $0.reason == .exact })
    #expect(index.search("").allSatisfy { $0.reason == .exact })
  }

  @Test func theWordTheRecipeHoldsIsReportedWhenTwoWordsAreClose() {
    let box = [
      SearchTestBox.entry("Soup", items: ["chickpeas"], id: 1),
      SearchTestBox.entry("Stew", items: ["chickens"], id: 2),
    ]
    let results = RecipeSearchIndex(box).search("chickn")
    #expect(results.map(\.reason.matched) == [["chickpeas"], ["chickens"]])
  }

  // MARK: Tiers and order

  @Test func theExactTierComesBeforeTheCloseTier() {
    // "chiken soup" is inside the first title, so it matches exactly; the other recipe needs
    // "chiken" forgiven.
    let box = [
      SearchTestBox.entry("Mochiken soup", id: 1),
      SearchTestBox.entry("Chicken soup", id: 2),
      SearchTestBox.entry("Another chicken soup", id: 3),
    ]
    let results = RecipeSearchIndex(box).search("chiken soup")
    #expect(results.map(\.tier) == [.exact, .close, .close])
    #expect(
      results.map { SearchTestBox.title(of: $0.id, in: box) }
        == ["Mochiken soup", "Another chicken soup", "Chicken soup"])
  }

  @Test func closeMatchesWithFewerMistakesComeFirstThenByTitle() {
    let box = [
      SearchTestBox.entry("Zucchini pie", id: 1),
      SearchTestBox.entry("Zuchini bake", id: 2),
      SearchTestBox.entry("Zucchini bread", id: 3),
    ]
    // "zuccchini" is nine letters, so two mistakes are forgiven. "zucchini" is one away and
    // "zuchini" is two.
    let titles = RecipeSearchIndex(box).search("zuccchini").map {
      SearchTestBox.title(of: $0.id, in: box)
    }
    #expect(titles == ["Zucchini bread", "Zucchini pie", "Zuchini bake"])
  }

  @Test func theTiersAreInOrder() {
    #expect(RecipeSearchIndex.Tier.exact < .close)
    #expect(RecipeSearchIndex.Tier.close < .partial)
  }

  // MARK: The line

  @Test func aTypoSaysWhatItMatched() {
    let reason = Reason(
      matched: ["chicken"], forgiven: [.init(typed: "chiken", matched: "chicken", kind: .typo)])
    #expect(reason.line == .plain("Matched chicken"))
    #expect(reason.shortLine == .plain("Matched chicken"))
  }

  @Test func forgivenWordsShowAsTheWordsTheyMatched() {
    let reason = Reason(
      matched: ["chocolate", "chip"],
      forgiven: [.init(typed: "choclate", matched: "chocolate", kind: .typo)])
    #expect(reason.line == .plain("Matched chocolate, chip"))
  }

  @Test func anotherNameSaysWhichWordItIsAnotherNameFor() {
    let reason = Reason(
      matched: ["aubergine"],
      forgiven: [.init(typed: "eggplant", matched: "aubergine", kind: .synonym)])
    #expect(reason.line == .plain("Matched aubergine, another name for eggplant"))
    #expect(reason.shortLine == .plain("Matched aubergine"))
  }

  @Test func anotherNameComesAfterTheWordsMatchedAsTheyWere() {
    let reason = Reason(
      matched: ["aubergine", "parmesan"],
      forgiven: [.init(typed: "eggplant", matched: "aubergine", kind: .synonym)])
    #expect(reason.line == .plain("Matched parmesan, aubergine, another name for eggplant"))
    #expect(reason.shortLine == .plain("Matched aubergine, parmesan"))
  }

  @Test func aTypoAndAnotherNameCanShareALine() {
    let reason = Reason(
      matched: ["chocolate", "cookie"],
      forgiven: [
        .init(typed: "choclate", matched: "chocolate", kind: .typo),
        .init(typed: "biscuit", matched: "cookie", kind: .synonym),
      ])
    #expect(reason.line == .plain("Matched chocolate, cookie, another name for biscuit"))
  }

  @Test func aPartialMatchSaysWhichWordIsMissing() {
    let reason = Reason(matched: ["spicy", "peanut"], missing: "noodles")
    #expect(reason.line == .plain("Matched spicy, peanut · no noodles"))
    #expect(reason.shortLine == .plain("Matched spicy, peanut · no noodles"))
  }

  @Test func aPartialMatchCanHaveForgivenWords() {
    let reason = Reason(
      matched: ["spicy", "peanut"],
      forgiven: [.init(typed: "peanutt", matched: "peanut", kind: .typo)], missing: "noodles")
    #expect(reason.line == .plain("Matched spicy, peanut · no noodles"))
  }

  @Test func anExactMatchHasNoLine() {
    #expect(Reason.exact.line == nil)
    #expect(Reason.exact.shortLine == nil)
  }

  @Test func theSectionIsCalledCloseMatches() {
    #expect(Copy.libraryNative.closeMatches == .plain("Close matches"))
  }
}
