import CauldronKit
import Foundation
import Testing

/// The index answers the way the per-recipe search always has, only from words prepared once.
/// `RecipeSearch.Query` is kept as the independent check: the old scan, run on every recipe.
@Suite("RecipeSearchIndex")
struct RecipeSearchIndexTests {
  private static func entry(
    _ title: String, _ rest: String = "", id: UInt8
  ) -> RecipeSearchIndex.Entry {
    RecipeSearchIndex.Entry(
      id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)), title: title,
      document: title.lowercased() + " " + rest.lowercased())
  }

  private static let box: [RecipeSearchIndex.Entry] = [
    entry("Tomato soup", "basil cream onions", id: 1),
    entry("Soup of the day", "leeks potatoes", id: 2),
    entry("Chicken soup", "carrots celery noodles", id: 3),
    entry("Crème brûlée", "cream eggs sugar vanilla", id: 4),
    entry("Chocolate chip cookies", "flour butter sugar eggs", id: 5),
    entry("Roast tomatoes", "garlic thyme olive oil", id: 6),
    entry("Mushroom risotto", "rice stock parmesan chopped onions", id: 7),
    entry("Pad thai", "rice noodles peanuts a quick weeknight dinner", id: 8),
    entry("Banana bread", "bananas flour walnuts", id: 9),
    entry("Beef stew", "beef carrots potatoes red wine", id: 10),
    entry("Tomato soup with grilled cheese", "bread cheddar", id: 11),
    entry("Pasta e fagioli", "beans pasta 100g tomatoes", id: 12),
    entry("Soup", "", id: 13),
  ]

  /// What the per-recipe search says: the recipes that match, a title that starts with the query
  /// first, then one with every word in the title, then the rest, each by title and id.
  private static func scan(_ entries: [RecipeSearchIndex.Entry], _ text: String) -> [UUID] {
    let query = RecipeSearch.Query(text)
    let found = entries.filter { query.matches(title: $0.title, document: $0.document) }
    return
      found
      .map { (entry: $0, rank: query.hasWords ? query.titleRank($0.title) : 0) }
      .sorted { a, b in
        if a.rank != b.rank { return a.rank > b.rank }
        let (x, y) = (a.entry.title.lowercased(), b.entry.title.lowercased())
        return x != y ? x < y : a.entry.id.uuidString < b.entry.id.uuidString
      }
      .map(\.entry.id)
  }

  static let queries = [
    "", "   ", "!!", "soup", "Soup", "so", "s", "tomatoes", "tomato", "tomatoe", "chopp", "chop",
    "the", "of the", "soup of", "soup of the day", "tomato soup", "soup tomato", "cream",
    "creme", "crème", "brûlée", "rice noodles", "noodle rice", "100g", "100", "10", "pasta,",
    "pasta e fagioli", "weeknight dinner", "a quick weeknight dinner", "quick", "zzz",
    "one two three four five six seven eight nine soup", "soup soup soup", "  chicken   soup ",
    "ing", "bananas", "banana", "potato", "potatoes carrots", "carrot beef", "cheese",
  ]

  @Test(arguments: queries)
  func answersAsThePerRecipeSearchDoes(_ text: String) {
    let index = RecipeSearchIndex(Self.box)
    #expect(index.search(text).map(\.id) == Self.scan(Self.box, text))
  }

  @Test func listsATitleThatStartsWithTheQueryFirstThenOnesWithEveryWordThenTheRest() {
    let index = RecipeSearchIndex(Self.box)
    func titles(_ text: String) -> [String] {
      index.search(text).compactMap { found in Self.box.first { $0.id == found.id }?.title }
    }
    #expect(titles("tomato soup") == ["Tomato soup", "Tomato soup with grilled cheese"])
    #expect(
      titles("soup") == [
        "Soup", "Soup of the day", "Chicken soup", "Tomato soup", "Tomato soup with grilled cheese",
      ])
    #expect(
      titles("tomatoes") == [
        "Roast tomatoes", "Tomato soup", "Tomato soup with grilled cheese", "Pasta e fagioli",
      ])
  }

  @Test func everyResultIsExactForNow() {
    let index = RecipeSearchIndex(Self.box)
    #expect(index.search("soup").allSatisfy { $0.tier == .exact })
    #expect(index.search("").allSatisfy { $0.tier == .exact })
  }

  @Test func blankTextMatchesEveryRecipeByTitle() {
    let index = RecipeSearchIndex(Self.box)
    let titles = index.search("").compactMap { found in
      Self.box.first { $0.id == found.id }?.title
    }
    #expect(titles.count == Self.box.count)
    #expect(titles == titles.sorted { $0.lowercased() < $1.lowercased() })
    #expect(!RecipeSearchIndex.hasWords("  ,. "))
    #expect(RecipeSearchIndex.hasWords("soup"))
    #expect(RecipeSearchIndex.hasWords("the"))
  }

  @Test func anEmptyBoxFindsNothing() {
    let index = RecipeSearchIndex([])
    #expect(index.search("soup").isEmpty)
    #expect(index.search("").isEmpty)
    #expect(index.words.isEmpty)
  }

  @Test func keepsTheBoxsDistinctWords() {
    let index = RecipeSearchIndex(Self.box)
    #expect(index.words == index.words.sorted())
    #expect(Set(index.words).count == index.words.count)
    for word in ["tomato", "tomatoes", "brûlée", "100g", "weeknight"] {
      #expect(index.words.contains(word))
    }
    #expect(!index.words.contains("zzz"))
  }

  @Test func remembersTheEntriesItWasBuiltFrom() {
    #expect(RecipeSearchIndex(Self.box).entries == Self.box)
    #expect(RecipeSearchIndex(Self.box.reversed()).entries == Self.box.reversed())
  }

  @Test func theOrderRecipesAreGivenInDoesNotChangeTheResults() {
    let forward = RecipeSearchIndex(Self.box)
    let backward = RecipeSearchIndex(Self.box.reversed())
    for text in Self.queries { #expect(forward.search(text) == backward.search(text)) }
  }

}
