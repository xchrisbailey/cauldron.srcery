import CauldronKit
import Testing

/// The search is the web's (`apps/api/src/Recipes.ts`): word prefixes over title, tags,
/// ingredients and description, stemmed the way Postgres's English search does it.
@Suite("RecipeSearch")
struct RecipeSearchTests {
  // MARK: Words

  @Test func wordsAreLowercasedRunsOfLettersAndDigits() {
    #expect(
      RecipeSearch.words("Tomato-Basil Soup, 2 cups!") == ["tomato", "basil", "soup", "2", "cups"])
    #expect(RecipeSearch.words("  ") == [])
    #expect(RecipeSearch.words("'&|!") == [])
    #expect(RecipeSearch.words("Crème brûlée") == ["crème", "brûlée"])
  }

  // MARK: Stems

  struct SameStem: Sendable {
    let words: [String]
  }

  static let families: [SameStem] = [
    .init(words: ["tomato", "tomatoes", "tomatoe"]),
    .init(words: ["potato", "potatoes"]),
    .init(words: ["berry", "berries"]),
    .init(words: ["cherry", "cherries"]),
    .init(words: ["cookie", "cookies"]),
    .init(words: ["pie", "pies"]),
    .init(words: ["box", "boxes"]),
    .init(words: ["dish", "dishes"]),
    .init(words: ["peach", "peaches"]),
    .init(words: ["glass", "glasses"]),
    .init(words: ["cheese", "cheeses"]),
    .init(words: ["sauce", "sauces"]),
    .init(words: ["bean", "beans"]),
    .init(words: ["egg", "eggs"]),
    .init(words: ["bake", "bakes", "baked", "baking"]),
    .init(words: ["chop", "chops", "chopped", "chopping"]),
    .init(words: ["slice", "sliced", "slicing", "slices"]),
    .init(words: ["mash", "mashed", "mashing"]),
    .init(words: ["fry", "fries", "fried", "frying"]),
    .init(words: ["dry", "dried", "drying"]),
    .init(words: ["leaf", "leafs"]),
  ]

  @Test(arguments: families)
  func formsOfAWordShareAStem(family: SameStem) {
    let stems = Set(family.words.map(RecipeSearch.stem))
    #expect(stems.count == 1, "\(family.words) -> \(stems)")
  }

  @Test func wordsThatAreNotFormsOfEachOtherKeepApart() {
    #expect(RecipeSearch.stem("rice") != RecipeSearch.stem("rib"))
    #expect(RecipeSearch.stem("bean") != RecipeSearch.stem("beet"))
    #expect(RecipeSearch.stem("pasta") != RecipeSearch.stem("pastry"))
  }

  @Test func wordsThatOnlyLookLikePluralsOrVerbsAreLeftAlone() {
    for word in ["hummus", "couscous", "asparagus", "swiss", "analysis", "gas", "bus"] {
      #expect(RecipeSearch.stem(word) == word)
    }
    // "string" and "bed" are not -ing and -ed forms.
    #expect(RecipeSearch.stem("string") == "string")
    #expect(RecipeSearch.stem("bed") == "bed")
    #expect(RecipeSearch.stem("seed") == "seed")
  }

  @Test func numbersAndMixedWordsAreNotStemmed() {
    #expect(RecipeSearch.stem("100") == "100")
    #expect(RecipeSearch.stem("100g") == "100g")
    #expect(RecipeSearch.stem("") == "")
    #expect(RecipeSearch.stem("é") == "é")
  }

  // MARK: Matching

  private func matches(_ query: String, title: String, document: String? = nil) -> Bool {
    RecipeSearch.Query(query).matches(title: title, document: document ?? title)
  }

  @Test func aBlankOrWordlessQueryMatchesEverything() {
    #expect(matches("", title: "Soup"))
    #expect(matches("   ", title: "Soup"))
    #expect(matches("'&|!", title: "Soup"))
    #expect(!RecipeSearch.Query("  ").hasWords)
    #expect(RecipeSearch.Query("soup").hasWords)
  }

  @Test func eachWordMustStartAWordInTheDocument() {
    let document = "Tomato soup basil white beans"
    #expect(matches("toma", title: "Dinner", document: document))
    #expect(matches("soup basil", title: "Dinner", document: document))
    #expect(matches("basil  SOUP ", title: "Dinner", document: document))
    // A middle of a word is not a word start.
    #expect(!matches("mato", title: "Dinner", document: document))
    #expect(!matches("soup parsley", title: "Dinner", document: document))
  }

  @Test func pluralsMatchBothWays() {
    #expect(matches("tomatoes", title: "Tomato soup"))
    #expect(matches("tomato", title: "Roasted tomatoes"))
    #expect(matches("berries", title: "Mixed berry crumble"))
    #expect(matches("berry", title: "Mixed berries"))
    #expect(matches("cookie", title: "Chocolate cookies"))
  }

  @Test func verbFormsMatch() {
    #expect(matches("baking", title: "Baked beans"))
    #expect(matches("bake", title: "Baked beans"))
    #expect(matches("chopped", title: "Chop suey"))
    #expect(matches("fried", title: "Fry bread"))
  }

  @Test func aWordStillBeingTypedMatchesByItsLetters() {
    // "chopp" is not the stem of "chopped", but it is the start of the word.
    #expect(matches("chopp", title: "Chopped salad"))
    #expect(matches("tomatoe", title: "Tomatoes"))
  }

  @Test func theWholeQueryAsASubstringOfTheTitleMatches() {
    // Not a word start, but the title contains it, as the web's `ilike` does.
    #expect(matches("mato so", title: "Tomato soup", document: "different words"))
    #expect(matches("MATO", title: "Tomato soup", document: "different words"))
  }

  @Test func theDescriptionIsPartOfTheDocument() {
    #expect(matches("crispy", title: "Fries", document: "Fries a crispy side"))
  }

  @Test func stopWordsAreIgnoredInTheQuery() {
    let document = "Salt pepper chicken"
    #expect(matches("salt and pepper", title: "Chicken", document: document))
    #expect(matches("the chicken", title: "Chicken", document: document))
  }

  @Test func aQueryOfOnlyStopWordsMatchesOnlyTitlesContainingIt() {
    #expect(matches("the", title: "The best soup", document: "the best soup"))
    #expect(!matches("the", title: "Soup", document: "soup is the best"))
  }

  @Test func onlyTheFirstEightWordsCount() {
    let query = "one two three four five six seven eight nine"
    #expect(matches(query, title: "x", document: "one two three four five six seven eight"))
    #expect(!matches("one two", title: "x", document: "one"))
  }

  @Test func punctuationInTheQueryIsIgnored() {
    #expect(matches("soup!", title: "Tomato soup"))
    #expect(matches("100%", title: "Soup", document: "Soup 100 percent"))
  }

  // MARK: Rank

  @Test func aTitleThatStartsWithTheQueryRanksFirstThenOnesWithEveryWord() {
    let query = RecipeSearch.Query("chicken so")
    #expect(query.titleRank("Chicken soup") == 2)
    #expect(RecipeSearch.Query("soup chicken").titleRank("Chicken soup") == 1)
    #expect(RecipeSearch.Query("chicken").titleRank("Soup with chicken") == 1)
    #expect(RecipeSearch.Query("chicken").titleRank("Roast beef") == 0)
    #expect(RecipeSearch.Query("").titleRank("Roast beef") == 0)
  }
}
