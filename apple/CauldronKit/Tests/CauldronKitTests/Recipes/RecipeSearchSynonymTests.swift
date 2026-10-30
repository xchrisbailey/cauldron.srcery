import CauldronKit
import Foundation
import Testing

/// Other names find recipes. The cases come from the test set of "Write a test set of searches
/// with mistakes" (#245), over the sample recipes and the ones a box will plausibly hold, and
/// the respellings that are too far from the word to be a typo.
@Suite("Recipe search synonyms")
struct RecipeSearchSynonymTests {
  struct Typed: Sendable, CustomTestStringConvertible {
    let text: String
    let finds: Set<String>
    var testDescription: String { text }
  }

  static let corpus: [Typed] = [
    Typed(text: "eggplant", finds: ["Aubergine parmigiana"]),
    Typed(text: "eggplants", finds: ["Aubergine parmigiana"]),
    Typed(text: "eggplant parmesan", finds: ["Aubergine parmigiana"]),
    Typed(text: "green onion", finds: ["Pad thai", "Kimchi fried rice"]),
    Typed(text: "green onions", finds: ["Pad thai", "Kimchi fried rice"]),
    Typed(text: "biscuits", finds: ["Brown butter chocolate chip cookies"]),
    Typed(text: "porridge", finds: ["Overnight oats"]),
    Typed(text: "oatmeal", finds: ["Overnight oats"]),
    Typed(text: "kimchee", finds: ["Kimchi fried rice"]),
    Typed(text: "kimchee rice", finds: ["Kimchi fried rice"]),
    Typed(text: "overnite oats", finds: ["Overnight oats"]),
    Typed(text: "overnite", finds: ["Overnight oats"]),
    // Another name always counts, even when the word typed is in the box.
    Typed(text: "scallion", finds: ["Pad thai", "Kimchi fried rice"]),
    Typed(text: "spring onion", finds: ["Kimchi fried rice", "Pad thai"]),
    Typed(text: "cilantro", finds: ["Guacamole", "Chicken tikka masala"]),
    Typed(text: "coriander", finds: ["Chicken tikka masala", "Guacamole"]),
    Typed(text: "yogurt", finds: ["Overnight oats", "Chicken tikka masala"]),
  ]

  /// Searches that must find nothing: another name for something the box doesn't hold.
  static let nothing = [
    "garbanzo", "garbanzos", "chickpea", "chickpeas", "prawn", "shrimp", "mince", "swede",
  ]

  @Test(arguments: corpus)
  func anotherNameFindsTheRecipe(_ typed: Typed) {
    #expect(Set(SearchTestBox.titles(typed.text)) == typed.finds)
  }

  @Test(arguments: nothing)
  func anotherNameForSomethingNotInTheBoxFindsNothing(_ text: String) {
    #expect(SearchTestBox.titles(text).isEmpty)
  }

  @Test func crispsAlsoFindChocolateChipRecipesThroughTheChipStem() {
    // Flagged for Chris on the PR: "chips" and "chip" share a stem, so another name for crisps
    // reaches chocolate chips. The thighs are the exact match ("crisp-skinned").
    let found = RecipeSearchIndex(SearchTestBox.corpus).search("crisps")
    #expect(
      found.map { SearchTestBox.title(of: $0.id) } == [
        "Weeknight chicken thighs with lemon and garlic", "Brown butter chocolate chip cookies",
      ])
    #expect(found.map(\.tier) == [.exact, .close])
  }

  // MARK: Tier and reason

  private func only(_ text: String) -> RecipeSearchIndex.Result? {
    let found = RecipeSearchIndex(SearchTestBox.corpus).search(text)
    return found.count == 1 ? found.first : nil
  }

  @Test func anotherNameIsACloseMatchThatSaysWhatItMatchedAndWhatWasTyped() {
    let result = only("eggplant")
    #expect(result?.tier == .close)
    #expect(
      result?.reason
        == .init(
          matched: ["aubergine"],
          forgiven: [.init(typed: "eggplant", matched: "aubergine", kind: .synonym)]))
    #expect(result?.reason.line?.text == "Matched aubergine, another name for eggplant")
  }

  @Test func aNameStillBeingTypedIsReportedAsTheNameItIs() {
    // "eggpl" is the start of "eggplant": the line names the other name, not the half word.
    let result = only("eggpl")
    #expect(result?.tier == .close)
    #expect(
      result?.reason.forgiven == [.init(typed: "eggplant", matched: "aubergine", kind: .synonym)])
    #expect(result?.reason.line?.text == "Matched aubergine, another name for eggplant")
    // A plural is the name too.
    #expect(
      only("eggplants")?.reason.line?.text == "Matched aubergine, another name for eggplant")
    // And a multi-word name with its last word half typed.
    let kimchi = RecipeSearchIndex(SearchTestBox.corpus).search("green oni").first {
      SearchTestBox.title(of: $0.id) == "Kimchi fried rice"
    }
    #expect(kimchi?.reason.line?.text == "Matched spring onion, another name for green onion")
  }

  @Test func aMultiWordNameIsOneMatchedWordAndOneTypedName() {
    let kimchi = RecipeSearchIndex(SearchTestBox.corpus).search("green onion").first {
      SearchTestBox.title(of: $0.id) == "Kimchi fried rice"
    }
    #expect(
      kimchi?.reason
        == .init(
          matched: ["spring onion"],
          forgiven: [.init(typed: "green onion", matched: "spring onion", kind: .synonym)]))
    #expect(kimchi?.reason.line?.text == "Matched spring onion, another name for green onion")
  }

  @Test func wordsMatchedAsTheyWereStayBesideTheOtherName() {
    let result = only("eggplant mozzarella")
    #expect(result?.tier == .close)
    #expect(result?.reason.matched == ["aubergine", "mozzarella"])
    #expect(
      result?.reason.line?.text == "Matched mozzarella, aubergine, another name for eggplant")
  }

  @Test func aWordInTheBoxStillFindsItsOtherNamesAfterTheExactMatches() {
    let found = RecipeSearchIndex(SearchTestBox.corpus).search("cilantro")
    #expect(found.map(\.tier) == [.exact, .close])
    #expect(found.map { SearchTestBox.title(of: $0.id) } == ["Guacamole", "Chicken tikka masala"])
    #expect(found.last?.reason.line?.text == "Matched coriander, another name for cilantro")
  }

  @Test func aRecipeThatMatchedExactlyIsNotListedAgainAsClose() {
    let box = [
      SearchTestBox.entry("Both", items: ["cilantro", "coriander"], id: 1),
      SearchTestBox.entry("Other", items: ["coriander"], id: 2),
    ]
    let found = RecipeSearchIndex(box).search("cilantro")
    #expect(found.map { SearchTestBox.title(of: $0.id, in: box) } == ["Both", "Other"])
    #expect(found.map(\.tier) == [.exact, .close])
  }

  @Test func aTypoStillFallsBackOnlyForAWordTheBoxLacks() {
    // "chiken" is in the box as a word, so it is not a typo of "chicken" in the other recipe.
    let box = [
      SearchTestBox.entry("Chicken soup", items: ["chicken"], id: 1),
      SearchTestBox.entry("Chiken fried", items: ["chiken"], id: 2),
    ]
    #expect(RecipeSearchIndex(box).search("chiken").map(\.tier) == [.exact])
  }

  @Test func aWordThatIsATypoAndAnotherNameOfTheSameWordReportsTheOtherName() {
    // "yoghurt" is one letter from "yogurt" and also another name for it.
    let box = [SearchTestBox.entry("Overnight oats", items: ["plain yogurt"], id: 1)]
    let result = RecipeSearchIndex(box).search("yoghurt").first
    #expect(result?.tier == .close)
    #expect(
      result?.reason.forgiven == [.init(typed: "yoghurt", matched: "yogurt", kind: .synonym)])
  }

  @Test func aTypoAndAnotherNameCanShareASearch() {
    let box = [SearchTestBox.entry("Roast aubergine", items: ["aubergine"], id: 1)]
    let result = RecipeSearchIndex(box).search("eggplant aubergene").first
    #expect(result?.tier == .close)
    #expect(result?.reason.forgiven.map(\.kind) == [.synonym, .typo])
  }

  // MARK: Partial matches

  @Test func anotherNameCountsInAPartialMatch() {
    // "bake" is the one word Aubergine parmigiana lacks; "eggplant" is its aubergine.
    let found = RecipeSearchIndex(SearchTestBox.corpus).search("eggplant tomato bake")
    #expect(found.map { SearchTestBox.title(of: $0.id) } == ["Aubergine parmigiana"])
    #expect(found.first?.tier == .partial)
    #expect(
      found.first?.reason
        == .init(
          matched: ["aubergine", "tomato"],
          forgiven: [.init(typed: "eggplant", matched: "aubergine", kind: .synonym)],
          missing: "bake"))
    #expect(
      found.first?.reason.line?.text
        == "Matched tomato, aubergine, another name for eggplant · no bake")
  }

  @Test func aMultiWordNameCountsInAPartialMatch() {
    let found = RecipeSearchIndex(SearchTestBox.corpus).search("green onion rice bake")
    #expect(found.map { SearchTestBox.title(of: $0.id) } == ["Kimchi fried rice", "Pad thai"])
    #expect(found.map(\.tier) == [.partial, .partial])
    #expect(found.first?.reason.missing == "bake")
    #expect(
      found.first?.reason.forgiven
        == [.init(typed: "green onion", matched: "spring onion", kind: .synonym)])
  }

  @Test func theWordsOfAMissingNameDoNotMatchTheNameAsAnotherName() {
    // Two words of "green onion" lacking is two words missing, not one.
    #expect(
      SearchTestBox.titles(
        "green onion rice bake",
        in: [
          SearchTestBox.entry("Plain rice", items: ["rice"], id: 1)
        ]
      ).isEmpty)
  }

  // MARK: Rules

  private func titles(_ text: String, groups: [[String]], _ items: [String]...) -> [String] {
    let box = items.enumerated().map { number, items in
      SearchTestBox.entry(items.joined(separator: " "), items: items, id: UInt8(number + 1))
    }
    let index = RecipeSearchIndex(box, synonyms: RecipeSearchSynonyms(groups: groups))
    return index.search(text).map { SearchTestBox.title(of: $0.id, in: box) }
  }

  @Test func aNameMatchesInBothDirections() {
    let groups = [["aubergine", "eggplant"]]
    #expect(titles("eggplant", groups: groups, ["aubergine"]) == ["aubergine"])
    #expect(titles("aubergine", groups: groups, ["eggplant"]) == ["eggplant"])
  }

  @Test func aGroupOfThreeMatchesFromAnyNameToTheOthers() {
    let groups = [["spring onion", "scallion", "green onion"]]
    for typed in groups[0] {
      for other in groups[0] where other != typed {
        #expect(titles(typed, groups: groups, [other]) == [other])
      }
    }
  }

  @Test func aMultiWordNameNeedsItsWordsTogetherAndInOrder() {
    let groups = [["spring onion", "scallion"]]
    #expect(titles("spring onion", groups: groups, ["scallion"]) == ["scallion"])
    #expect(titles("onion spring", groups: groups, ["scallion"]).isEmpty)
    #expect(titles("spring", groups: groups, ["scallion"]).isEmpty)
    #expect(titles("spring red onion", groups: groups, ["scallion"]).isEmpty)
    #expect(titles("spring onion soup", groups: groups, ["scallion", "soup"]) == ["scallion soup"])
  }

  @Test func aMultiWordNameFindsASingleWordAndTheOtherWayAround() {
    let groups = [["spring onion", "scallion"]]
    #expect(titles("scallion", groups: groups, ["spring", "onion"]) == ["spring onion"])
  }

  @Test func theLastWordOfAMultiWordNameMayStillBeBeingTyped() {
    let groups = [["spring onion", "scallion"]]
    #expect(titles("spring oni", groups: groups, ["scallion"]) == ["scallion"])
    #expect(titles("spring o", groups: groups, ["scallion"]) == ["scallion"])
    // Only the last word: an earlier word is whole.
    #expect(titles("spr onion", groups: groups, ["scallion"]).isEmpty)
    #expect(titles("spring oni soup", groups: groups, ["scallion", "soup"]).isEmpty)
  }

  @Test func aOneWordNameIsMatchedByItsStartFromFiveLetters() {
    // "egg" and "eggp" are the start of "eggplant" too, and finding aubergines for them would be
    // noise under every egg.
    let groups = [["eggplant", "aubergine"]]
    #expect(titles("egg", groups: groups, ["aubergine"]).isEmpty)
    #expect(titles("eggp", groups: groups, ["aubergine"]).isEmpty)
    #expect(titles("eggpl", groups: groups, ["aubergine"]) == ["aubergine"])
    #expect(titles("eggplan", groups: groups, ["aubergine"]) == ["aubergine"])
    // Only the word being typed, which is the last.
    #expect(titles("eggpl soup", groups: groups, ["aubergine", "soup"]).isEmpty)
  }

  @Test func aNameWithItsWordsAlreadyInTheBoxStillExpands() {
    // "green" and "onion" are both in the box, but no recipe has both.
    let groups = [["green onion", "scallion"]]
    #expect(
      titles("green onion", groups: groups, ["green beans"], ["red onion"], ["scallion"])
        == ["scallion"])
    #expect(
      titles("green onion", groups: groups, ["green onion"], ["scallion"])
        == ["green onion", "scallion"])
  }

  @Test func anotherNameDoesNotChainIntoAnotherGroup() {
    // foo = bar and bar = baz are two groups: foo reaches bar, but not baz through it.
    let groups = [["foo", "bar"], ["bar", "baz"]]
    #expect(titles("foo", groups: groups, ["bar"], ["baz"]) == ["bar"])
    #expect(titles("baz", groups: groups, ["bar"], ["foo"]) == ["bar"])
    // A name in both groups reaches both.
    #expect(Set(titles("bar", groups: groups, ["foo"], ["baz"])) == ["foo", "baz"])
  }

  @Test func aNameWithPunctuationOrAStopWordIsMatchedByItsWords() {
    let groups = [
      ["self-raising flour", "self-rising flour"], ["bicarbonate of soda", "baking soda"],
    ]
    #expect(
      titles("self-raising flour", groups: groups, ["self-rising", "flour"])
        == ["self-rising flour"])
    #expect(titles("bicarbonate of soda", groups: groups, ["baking soda"]) == ["baking soda"])
    #expect(
      titles("baking soda", groups: groups, ["bicarbonate", "soda"]) == ["bicarbonate soda"])
  }

  @Test func accentsInANameAreFolded() {
    let groups = [["crème fraîche", "sour cream"]]
    #expect(titles("creme fraiche", groups: groups, ["sour cream"]) == ["sour cream"])
    #expect(titles("sour cream", groups: groups, ["creme fraiche"]) == ["creme fraiche"])
    #expect(titles("crème fraîche", groups: groups, ["sour cream"]) == ["sour cream"])
  }

  // MARK: The table

  @Test func noNameIsInTwoGroupsOfTheTable() {
    let names = RecipeSearchSynonyms.standard.groups.flatMap { $0 }
    #expect(Set(names).count == names.count)
  }

  @Test func everyGroupOfTheTableHasTwoOrMoreNamesAndEveryNameIsLowercase() {
    for group in RecipeSearchSynonyms.standard.groups {
      #expect(group.count >= 2)
      for name in group { #expect(name == name.lowercased() && !name.isEmpty) }
    }
  }

  @Test func theTableHasAnEntryForEachCaseThatIsInTheParentSpec() {
    let names = Set(RecipeSearchSynonyms.standard.groups.flatMap { $0 })
    for name in [
      "aubergine", "eggplant", "spring onion", "scallion", "green onion", "bell pepper",
      "chickpea", "garbanzo", "bicarbonate of soda", "baking soda", "golden syrup", "corn syrup",
      "spring roll", "egg roll", "kimchee", "kimchi", "overnite", "overnight",
    ] {
      #expect(names.contains(name), "\(name)")
    }
  }
}
