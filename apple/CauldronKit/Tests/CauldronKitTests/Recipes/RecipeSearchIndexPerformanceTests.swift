import CauldronKit
import Foundation
import Testing

/// A box of 1,000 recipes, searched as someone types. Timings are medians, so one slow step on
/// a busy machine doesn't fail the run.
@Suite("RecipeSearchIndex at 1,000 recipes")
struct RecipeSearchIndexPerformanceTests {
  /// A small repeatable generator, so the box is the same on every run.
  private struct Dice {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15

    mutating func roll(_ bound: Int) -> Int {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((state >> 33) % UInt64(bound))
    }

    mutating func pick(_ options: [String]) -> String { options[roll(options.count)] }
  }

  private static let foods = [
    "chicken", "beef", "pork", "lamb", "salmon", "cod", "tofu", "lentil", "chickpea", "rice",
    "noodle", "potato", "tomato", "onion", "garlic", "ginger", "carrot", "celery", "leek",
    "spinach", "kale", "broccoli", "cauliflower", "pumpkin", "squash", "mushroom", "pepper",
    "aubergine", "courgette", "cabbage", "apple", "pear", "banana", "lemon", "orange", "berry",
    "chocolate", "vanilla", "cinnamon", "walnut", "almond", "peanut", "coconut", "yoghurt",
    "cheese", "butter", "cream", "egg", "flour", "sugar", "honey", "basil", "thyme", "parsley",
    "coriander", "cumin", "paprika", "turmeric", "mustard", "vinegar",
  ]
  private static let dishes = [
    "soup", "stew", "curry", "salad", "risotto", "pie", "tart", "cake", "bread", "cookies",
    "pasta", "bake", "roast", "stir fry", "tacos", "burgers", "pancakes", "porridge",
    "dumplings", "casserole", "gratin", "fritters", "skewers", "wraps", "bowl",
  ]
  private static let styles = [
    "spicy", "creamy", "crispy", "smoky", "sticky", "slow cooked", "one pan", "quick", "easy",
    "roasted", "grilled", "baked", "fresh", "warm", "classic", "weeknight", "sunday",
  ]
  private static let tags = [
    "dinner", "lunch", "breakfast", "dessert", "vegan", "vegetarian", "freezer", "kids",
  ]

  /// Recipes with a title of three words, five to eight ingredients, up to three tags and a
  /// description of a dozen words or more.
  static func box(_ count: Int) -> [RecipeSearchIndex.Entry] {
    var dice = Dice()
    return (0..<count).map { number in
      let title = [
        dice.pick(styles), dice.pick(foods), dice.pick(dishes),
      ].joined(separator: " ")
      let items = (0..<(5 + dice.roll(4))).map { _ in "\(1 + dice.roll(4)) cups \(dice.pick(foods))"
      }
      let picked = (0..<(1 + dice.roll(3))).map { _ in dice.pick(tags) }
      let description = (0..<(12 + dice.roll(10))).map { _ in
        dice.pick([foods, dishes, styles][dice.roll(3)])
      }
      let document = ([title] + items + picked + description).joined(separator: " ")
      return RecipeSearchIndex.Entry(
        id: UUID(
          uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(number >> 8), UInt8(number & 255), 1)),
        title: title, document: document)
    }
  }

  private static func prefixes(of word: String) -> [String] {
    (1...word.count).map { String(word.prefix($0)) }
  }

  /// The median time to answer each of `texts`, in the quietest of several rounds. Other tests
  /// run beside this one and slow a round down; the quietest is the least disturbed.
  private static func medianSearch(_ texts: [String], on index: RecipeSearchIndex) -> Duration {
    let clock = ContinuousClock()
    let rounds = (0..<9).map { _ in
      let samples = texts.map { text in clock.measure { _ = index.search(text) } }
      return samples.sorted()[samples.count / 2]
    }
    return rounds.min() ?? .zero
  }

  @Test func buildingTheIndexForAThousandRecipesTakesUnder50Milliseconds() {
    let entries = Self.box(1_000)
    let clock = ContinuousClock()
    let built = (0..<9).map { _ in clock.measure { _ = RecipeSearchIndex(entries) } }.min() ?? .zero
    print("RecipeSearchIndex build, 1,000 recipes: quietest of 9 \(built)")
    #expect(built < .milliseconds(50))
  }

  @Test func eachKeystrokeOfATypedWordTakesUnder2Milliseconds() {
    let index = RecipeSearchIndex(Self.box(1_000))
    let typed = Self.prefixes(of: "chicken") + Self.prefixes(of: "casserole")
    let median = Self.medianSearch(typed, on: index)
    print("RecipeSearchIndex keystroke, 1,000 recipes: median, quietest of 9 rounds \(median)")
    #expect(median < .milliseconds(2))
  }

  @Test func eachKeystrokeOfAMisspeltWordTakesUnder2Milliseconds() {
    let index = RecipeSearchIndex(Self.box(1_000))
    let typed = Self.prefixes(of: "chikcen")
    let median = Self.medianSearch(typed, on: index)
    print(
      "RecipeSearchIndex misspelt keystroke, 1,000 recipes: median, quietest of 9 rounds \(median)")
    #expect(median < .milliseconds(2))
  }

  @Test func eachKeystrokeOfAnotherNameTakesUnder2Milliseconds() {
    // "eggplant" is another name for the box's aubergine, and "bell pepper" for its capsicum.
    let index = RecipeSearchIndex(Self.box(1_000))
    let typed = Self.prefixes(of: "eggplant") + Self.prefixes(of: "bell pepper")
    let median = Self.medianSearch(typed, on: index)
    print("RecipeSearchIndex other-name keystroke, 1,000 recipes: median, quietest of 9 \(median)")
    #expect(median < .milliseconds(2))
    #expect(index.search("eggplant").count == index.search("aubergine").count)
    #expect(index.search("eggplant").allSatisfy { $0.tier == .close })
  }

  @Test func eachKeystrokeOfAThreeWordMisspeltSearchTakesUnder2Milliseconds() {
    let index = RecipeSearchIndex(Self.box(1_000))
    // Three words, so a recipe lacking one still matches, and the first is misspelt.
    let typed = Self.prefixes(of: "chikcen tomato casserole")
    let median = Self.medianSearch(typed, on: index)
    print(
      "RecipeSearchIndex three-word misspelt keystroke, 1,000 recipes: median, quietest of 9 rounds \(median)"
    )
    #expect(median < .milliseconds(2))
  }

  @Test func theBoxIsBigEnoughToMatterAndTheKeystrokesFindThings() {
    let index = RecipeSearchIndex(Self.box(1_000))
    #expect(index.entries.count == 1_000)
    #expect(index.words.count > 100)
    #expect(index.search("c").count > 100)
    #expect(index.search("chicken").count > 10)
    #expect(index.search("chikcen").count == index.search("chicken").count)
    #expect(index.search("chikcen").allSatisfy { $0.tier == .close })
    let partial = index.search("chikcen tomato casserole")
    #expect(partial.contains { $0.tier == .partial })
    #expect(partial.allSatisfy { $0.tier != .exact })
  }
}
