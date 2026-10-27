import CauldronKit
import Foundation
import Testing

@Suite("Search keyword fingerprint")
struct SearchKeywordFingerprintTests {
  private let kimchi = SearchKeywordInputs(
    title: "Kimchi Fried Rice", ingredients: ["Day-old rice", "Kimchi"],
    tags: ["Rice", "Dinner"], description: "Uses up leftover rice.")

  /// The literal comes from a separate implementation of the same recipe, so a change to the
  /// canonical string or the hash, or a hash that differs between processes, fails here.
  @Test func theFingerprintIsAStableLiteral() {
    #expect(kimchi.fingerprint == "305c3e272cacecb6")
  }

  @Test func tagOrderDoesNotMatter() {
    var reversed = kimchi
    reversed.tags = ["Dinner", "Rice"]
    #expect(reversed.fingerprint == kimchi.fingerprint)
  }

  @Test func caseSpacingAndAccentFormDoNotMatter() {
    let one = SearchKeywordInputs(title: "Crème brûlée", ingredients: ["Cream"], tags: [])
    let two = SearchKeywordInputs(
      title: "  CRE\u{0300}ME BRU\u{0302}LE\u{0301}E ", ingredients: [" cream\n"], tags: [""])
    #expect(two.title != one.title)
    #expect(one.fingerprint == two.fingerprint)
  }

  @Test func theWordsThatFeedTheModelChangeIt() {
    var edited = kimchi
    edited.ingredients = ["Day-old rice", "Kimchi", "Egg"]
    #expect(edited.fingerprint != kimchi.fingerprint)
    edited = kimchi
    edited.ingredients = ["Kimchi", "Day-old rice"]
    #expect(edited.fingerprint != kimchi.fingerprint)
    edited = kimchi
    edited.title = "Kimchi Rice"
    #expect(edited.fingerprint != kimchi.fingerprint)
    edited = kimchi
    edited.tags = ["Rice"]
    #expect(edited.fingerprint != kimchi.fingerprint)
    edited = kimchi
    edited.description = nil
    #expect(edited.fingerprint != kimchi.fingerprint)
  }

  @Test func aWordMovedBetweenPartsChangesIt() {
    let title = SearchKeywordInputs(title: "Rice", ingredients: [], tags: [])
    let ingredient = SearchKeywordInputs(title: "", ingredients: ["Rice"], tags: [])
    #expect(title.fingerprint != ingredient.fingerprint)
  }
}

@Suite("Search keyword prompt")
struct SearchKeywordPromptTests {
  private let inputs = SearchKeywordInputs(
    title: "Kimchi Fried Rice", ingredients: ["Day-old rice", "Kimchi", "Egg"],
    tags: ["Rice", "Dinner"], description: "Uses up leftover rice.")

  @Test func theInstructionsNameEveryKindOfKeyword() {
    let system = SearchKeywordPrompt.system
    for name in [
      "other ingredient names", "dish", "cuisine", "flavour", "method", "occasion", "uses-up",
    ] {
      #expect(system.localizedCaseInsensitiveContains(name), "missing \(name)")
    }
    #expect(system.contains("\(SearchKeywordAnswer.wordLimit)"))
  }

  @Test func theUserPromptCarriesTheInputs() {
    let user = SearchKeywordPrompt.user(for: inputs)
    #expect(user.contains("Kimchi Fried Rice"))
    for line in ["Day-old rice", "Kimchi", "Egg", "Rice", "Dinner", "Uses up leftover rice."] {
      #expect(user.contains(line), "missing \(line)")
    }
    let ingredients = user.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(ingredients == ["- Day-old rice", "- Kimchi", "- Egg"])
  }

  @Test func emptyPartsAreLeftOut() {
    let bare = SearchKeywordInputs(title: "Toast", ingredients: [], tags: [])
    let user = SearchKeywordPrompt.user(for: bare)
    #expect(user.contains("Toast"))
    #expect(!user.localizedCaseInsensitiveContains("ingredients"))
    #expect(!user.localizedCaseInsensitiveContains("tags"))
    #expect(!user.localizedCaseInsensitiveContains("description"))
  }

  @Test func theAnswerHasAListForEachKind() {
    let answer = SearchKeywordAnswer(
      otherIngredients: ["scallion"], dish: ["fried rice"], cuisine: ["korean"],
      flavour: ["spicy"], method: ["stir-fry"], occasion: ["weeknight"], usesUp: ["leftover rice"])
    #expect(answer.keywords.contains("fried rice"))
    #expect(SearchKeywordAnswer.Field.allCases.count == 7)
  }
}

@Suite("Search keyword flattening")
struct SearchKeywordFlatteningTests {
  private func words(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
  }

  @Test func theListsFlattenToOneLineOfText() {
    let answer = SearchKeywordAnswer(
      otherIngredients: ["Scallion"], dish: ["Fried Rice"], cuisine: ["Korean"], flavour: ["spicy"])
    let text = answer.keywords
    #expect(!text.contains("\n"))
    for part in ["scallion", "fried rice", "korean", "spicy"] {
      #expect(text.contains(part))
    }
  }

  @Test func entriesAreTrimmedLowercasedAndNotRepeated() {
    let answer = SearchKeywordAnswer(
      otherIngredients: ["  Rice ", "rice"], dish: ["RICE", "", "  "], cuisine: ["Korean\nfood"])
    #expect(answer.keywords == "rice, korean food")
  }

  @Test func anEmptyAnswerIsEmpty() {
    #expect(SearchKeywordAnswer().keywords == "")
  }

  @Test func theTextNeverPassesThirtyWords() {
    let many = (1...40).map { "word\($0)" }
    let answer = SearchKeywordAnswer(otherIngredients: many)
    #expect(words(answer.keywords) == 30)
    #expect(SearchKeywordAnswer.wordLimit == 30)
  }

  @Test func anEntryThatWouldPassTheCapIsLeftOutWhole() {
    let long = (1...29).map { "w\($0)" }.joined(separator: " ")
    let answer = SearchKeywordAnswer(otherIngredients: [long, "two words"], dish: ["one"])
    #expect(answer.keywords == "one, " + long)
  }

  @Test func everyKindGetsAShareBeforeAnyGetsTwo() {
    let filler = (1...40).map { "filler\($0)" }
    let answer = SearchKeywordAnswer(
      otherIngredients: filler, dish: ["fried rice"], cuisine: ["korean"], usesUp: ["leftovers"])
    let text = answer.keywords
    #expect(words(text) <= 30)
    for part in ["fried rice", "korean", "leftovers"] { #expect(text.contains(part)) }
  }
}
