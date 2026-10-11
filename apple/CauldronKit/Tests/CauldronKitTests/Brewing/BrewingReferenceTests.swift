import CauldronKit
import Testing

// Edge cases beyond the reference's own tests. Each expected value is what the TypeScript
// `stepIngredients` returns for the input (run with `bun`), so they pin the places a port is
// most likely to drift: word boundaries, plurals, case, punctuation, Unicode, names inside other
// names, and the order ties are broken in.

struct BrewingCase: CustomTestStringConvertible, Sendable {
  let testDescription: String
  let items: [String]
  let steps: [String]
  let expected: [[Int]]
  /// Whether `items` are item keys as they are, instead of items to run through `ingredientKey`.
  let raw: Bool

  init(_ name: String, items: [String], steps: [String], expected: [[Int]], raw: Bool = false) {
    self.testDescription = name
    self.items = items
    self.steps = steps
    self.expected = expected
    self.raw = raw
  }

  var result: [[Int]] {
    let ingredients = raw ? brewingIngredients(keys: items) : brewingIngredients(items)
    return stepIngredients(
      steps.map { Step(section: nil, text: $0, timerSeconds: nil) }, ingredients)
  }
}

@Suite("stepIngredients edges")
struct BrewingReferenceTests {
  static let cases: [BrewingCase] = [
    BrewingCase(
      "an item inside a longer word is not named",
      items: ["pepper"],
      steps: ["Add the peppercorns.", "Add the pepperoni.", "Add the pepper."],
      expected: [[], [], [0]]
    ),
    BrewingCase(
      "oil inside boil",
      items: ["oil"],
      steps: ["Bring to a boil.", "Add oil."],
      expected: [[], [0]]
    ),
    BrewingCase(
      "a trailing word of a longer word",
      items: ["butter"],
      steps: ["Add the butterscotch.", "Add the peanutbutter.", "Stir in butter"],
      expected: [[], [], [0]]
    ),
    BrewingCase(
      "hyphenated words are one word",
      items: ["green onion", "onion", "stir-fry sauce"],
      steps: ["Add the green-onion.", "Stir-fry the onion.", "Use the stir-fry sauce."],
      expected: [[], [1], [2]]
    ),
    BrewingCase(
      "a hyphenated item",
      items: ["extra-virgin olive oil"],
      steps: [
        "Drizzle extra-virgin olive oil.", "Drizzle the oil.", "Drizzle extra virgin olive oil.",
      ],
      expected: [[0], [0], [0]]
    ),
    BrewingCase(
      "a lone hyphen is a word",
      items: ["salt"],
      steps: ["Salt - then pepper.", "salt-and-pepper"],
      expected: [[0], []]
    ),
    BrewingCase(
      "plurals either way",
      items: ["berries", "tomato", "bay leaves", "peaches", "radish"],
      steps: [
        "Add the berry and tomatoes.", "Tear the bay leaf.", "Slice the peaches and the radishes.",
      ],
      expected: [[0, 1], [2], [3, 4]]
    ),
    BrewingCase(
      "words ending in ss, us, is",
      items: ["glass", "asparagus", "hummus", "oats"],
      steps: ["Fill the glasses.", "Roast the asparagus with hummus.", "Fold in oat."],
      expected: [[0], [1, 2], []]
    ),
    BrewingCase(
      "short words are not singularized",
      items: ["gas", "peas"],
      steps: ["Light the gas.", "Add pea."],
      expected: [[0], [1]]
    ),
    BrewingCase(
      "mixed case items and steps",
      items: ["Olive Oil", "RED ONION"],
      steps: ["warm OLIVE oil", "Dice the Red Onions"],
      expected: [[0], [1]]
    ),
    BrewingCase(
      "punctuation between words",
      items: ["salt", "black pepper", "garlic"],
      steps: [
        "Salt/pepper, to taste.", "(salt) [black pepper] {garlic}", "garlic;salt:black-pepper",
        "\"black\" 'pepper'",
      ],
      expected: [[0, 1], [0, 1, 2], [0, 2], [1]]
    ),
    BrewingCase(
      "apostrophes split words",
      items: ["baker's yeast", "yeast"],
      steps: ["Add baker's yeast.", "Add bakers yeast.", "Add yeast."],
      expected: [[0], [1], [1]]
    ),
    BrewingCase(
      "underscores and symbols split words",
      items: ["olive oil", "garlic"],
      steps: ["olive_oil", "garlic_cloves", "garlic+olive*oil", "garlic&olive oil"],
      expected: [[0], [1], [0, 1], [0, 1]]
    ),
    BrewingCase(
      "digits are part of words",
      items: ["egg", "00 flour", "2% milk"],
      steps: ["Add 2 eggs.", "Sift 00 flour.", "Pour 2% milk.", "Use 2egg."],
      expected: [[0], [1], [2], []]
    ),
    BrewingCase(
      "superscripts and fractions stay in the word",
      items: ["sugar"],
      steps: ["Add 2\u{BD} sugar.", "Add \u{BD} sugar.", "Add x\u{B2} sugar."],
      expected: [[0], [0], [0]],
      raw: true
    ),
    BrewingCase(
      "unusual whitespace separates words",
      items: ["olive oil", "salt"],
      steps: [
        "olive\u{A0}oil", "olive\u{2003}oil", "olive\u{FEFF}oil", "olive\u{85}oil",
        "olive\u{200B}oil", "olive\u{9}oil\u{A}salt\u{D}\u{A}", "  salt  ",
      ],
      expected: [[0], [0], [0], [0], [0], [0, 1], [1]]
    ),
    BrewingCase(
      "empty and blank steps",
      items: ["salt"],
      steps: ["", "   ", "\u{A}"],
      expected: [[], [], []]
    ),
    BrewingCase(
      "accents compare as written",
      items: ["jalape\u{F1}o", "cr\u{E8}me fra\u{EE}che"],
      steps: [
        "Add jalape\u{F1}os.", "Add JALAPE\u{D1}O.", "Add jalapen\u{303}o.",
        "Stir in cr\u{E8}me fra\u{EE}che.", "Stir in creme fraiche.",
        "Stir in cre\u{300}me fra\u{EE}che.",
      ],
      expected: [[0], [0], [], [1], [], [1]],
      raw: true
    ),
    BrewingCase(
      "non-latin scripts",
      items: [
        "\u{5375}", "\u{44F}\u{439}\u{446}\u{430}", "\u{3A3}\u{391}\u{39B}\u{391}\u{3A4}\u{391}",
      ],
      steps: [
        "\u{5375}\u{3092}\u{5272}\u{308B}\u{3002}",
        "\u{414}\u{43E}\u{431}\u{430}\u{432}\u{44C}\u{442}\u{435} \u{44F}\u{439}\u{446}\u{430}.",
        "\u{44F}\u{439}\u{446}\u{43E}",
        "\u{3A0}\u{3C1}\u{3CC}\u{3C3}\u{3B8}\u{3B5}\u{3C3}\u{3B5} \u{3C3}\u{3B1}\u{3BB}\u{3B1}\u{3C4}\u{3B1}",
        "\u{3C3}\u{3B1}\u{3BB}\u{3B1}\u{3C4}\u{3B1}",
      ],
      expected: [[], [1], [], [2], [2]],
      raw: true
    ),
    BrewingCase(
      "final sigma",
      items: ["\u{39F}\u{394}\u{3A5}\u{3A3}\u{3A3}\u{395}\u{3A5}\u{3A3}", "\u{391}\u{3A3}"],
      steps: [
        "\u{3BF}\u{3B4}\u{3C5}\u{3C3}\u{3C3}\u{3B5}\u{3C5}\u{3C2}",
        "\u{3BF}\u{3B4}\u{3C5}\u{3C3}\u{3C3}\u{3B5}\u{3C5}\u{3C3}",
        "\u{39F}\u{394}\u{3A5}\u{3A3}\u{3A3}\u{395}\u{3A5}\u{3A3}",
      ],
      expected: [[0], [], [0]],
      raw: true
    ),
    BrewingCase(
      "dotted capital i",
      items: ["ice", "\u{130}ce"],
      steps: ["\u{130}ce cream", "ice cream", "i\u{307}ce"],
      expected: [[1], [0], [1]],
      raw: true
    ),
    BrewingCase(
      "emoji and symbols break words",
      items: ["egg"],
      steps: ["\u{1F95A}egg", "egg\u{1F95A}", "egg\u{2122}"],
      expected: [[0], [0], [0]]
    ),
    BrewingCase(
      "letters beyond the BMP",
      items: ["red \u{1D49C}\u{1D49C}", "\u{1D49C}"],
      steps: ["Add the \u{1D49C}\u{1D49C}.", "Add \u{1D49C}."],
      expected: [[0], [1]],
      raw: true
    ),
    BrewingCase(
      "head length counts UTF-16 units",
      items: ["red \u{1D49C}\u{1D49C}", "red ab", "red abc"],
      steps: ["the \u{1D49C}\u{1D49C}", "the ab", "the abc"],
      expected: [[0], [], [2]],
      raw: true
    ),
    BrewingCase(
      "last words under three units are never matched alone",
      items: ["red ox", "red oxo", "small pea"],
      steps: ["Add the ox.", "Add the oxo.", "Add the pea."],
      expected: [[], [1], [2]]
    ),
    BrewingCase(
      "every vague last word",
      items: [
        "lemon juice", "lemon zest", "bay leaf", "garlic powder", "poppy seed", "soy sauce",
        "beef stock", "tap water",
      ],
      steps: [
        "juice zest leaf powder seed sauce stock water",
        "lemon juice, lemon zest, bay leaf, garlic powder, poppy seed, soy sauce, beef stock, tap water",
        "juices zests leaves powders seeds sauces stocks waters",
      ],
      expected: [[], [0, 1, 2, 3, 4, 5, 6, 7], []]
    ),
    BrewingCase(
      "a single word item needs the whole name",
      items: ["pepper", "juice"],
      steps: ["Add the pepper.", "Add the juice."],
      expected: [[0], [1]]
    ),
    BrewingCase(
      "last word shared by several items",
      items: ["red pepper", "green pepper", "black pepper"],
      steps: [
        "Add the pepper.", "Add the red pepper and the pepper.", "Add black pepper.",
        "Add black pepper, then the pepper.",
      ],
      expected: [[0, 1, 2], [0], [2], [2]]
    ),
    BrewingCase(
      "last word claimed or not",
      items: ["red bell pepper", "black pepper"],
      steps: [
        "Add black pepper and pepper.", "Season with pepper, then black pepper.",
        "Red bell pepper, black pepper.",
      ],
      expected: [[1], [1], [0, 1]]
    ),
    BrewingCase(
      "the same ingredient in several steps",
      items: ["onion", "garlic"],
      steps: ["Chop the onion.", "Fry the onion and garlic.", "Garlic, garlic, garlic.", "Serve."],
      expected: [[0], [0, 1], [1], []]
    ),
    BrewingCase(
      "the same ingredient twice in a step",
      items: ["red onion", "onion"],
      steps: ["Fry the onion, then the red onion, then the onion again."],
      expected: [[0, 1]]
    ),
    BrewingCase(
      "duplicate ingredients",
      items: ["onion", "onion", "salt"],
      steps: ["Add the onion.", "Add salt."],
      expected: [[0], [2]]
    ),
    BrewingCase(
      "duplicate longer ingredients",
      items: ["green onion", "green onion"],
      steps: ["Add the onion.", "Add the green onion."],
      expected: [[0, 1], [0]]
    ),
    BrewingCase(
      "a name that is a substring of another",
      items: ["pepper", "red bell pepper", "bell pepper"],
      steps: [
        "Add the bell pepper.", "Add the red bell pepper.", "Add the pepper.",
        "Add the red pepper.",
      ],
      expected: [[2], [1], [0], [0]]
    ),
    BrewingCase(
      "a name inside the middle of another",
      items: ["olive", "olive oil", "oil"],
      steps: ["Add olive oil.", "Add olives.", "Add oil."],
      expected: [[1], [0], [2]]
    ),
    BrewingCase(
      "three words nest",
      items: ["tomato", "tomato paste", "double concentrated tomato paste"],
      steps: [
        "Add double concentrated tomato paste.", "Add tomato paste.", "Add tomato.",
        "Add the paste.",
      ],
      expected: [[2], [1], [0], [1, 2]]
    ),
    BrewingCase(
      "overlapping names",
      items: ["red onion", "onion soup", "soup mix"],
      steps: ["red onion soup", "red onion soup mix", "onion soup mix"],
      expected: [[0, 1], [0, 1, 2], [1, 2]]
    ),
    BrewingCase(
      "overlapping names of equal length",
      items: ["salt pepper", "pepper corn"],
      steps: ["salt pepper corn", "pepper corn salt pepper"],
      expected: [[0, 1], [0, 1]]
    ),
    BrewingCase(
      "a partly claimed span still counts",
      items: ["aaa bbb ccc", "bbb ccc ddd", "ccc ddd eee"],
      steps: ["aaa bbb ccc ddd eee", "bbb ccc ddd eee", "aaa bbb ccc ddd"],
      expected: [[0, 1, 2], [1, 2], [0, 1]]
    ),
    BrewingCase(
      "ties keep list order",
      items: ["chili oil", "olive oil", "oil"],
      steps: ["chili olive oil", "olive chili oil"],
      expected: [[1], [0]]
    ),
    BrewingCase(
      "no ingredients",
      items: [],
      steps: ["Add salt.", ""],
      expected: [[], []]
    ),
    BrewingCase(
      "no steps",
      items: ["salt"],
      steps: [],
      expected: []
    ),
    BrewingCase(
      "neither",
      items: [],
      steps: [],
      expected: []
    ),
    BrewingCase(
      "an empty item key",
      items: ["", "salt"],
      steps: ["Add salt.", ""],
      expected: [[1], []],
      raw: true
    ),
    BrewingCase(
      "blank and punctuation only keys",
      items: ["   ", "!!!", "-"],
      steps: ["Add - salt!!!", "-"],
      expected: [[2], [2]],
      raw: true
    ),
    BrewingCase(
      "keys that are not normalized",
      items: ["Large Eggs", "RED ONIONS", "olive-oil", "salt, pepper"],
      steps: ["Crack the eggs.", "Slice the red onion.", "olive-oil", "Add the salt pepper."],
      expected: [[0], [1], [2], [3]],
      raw: true
    ),
    BrewingCase(
      "keys with size words and parentheses",
      items: ["2 large (eggs)", "medium onions"],
      steps: ["Crack 2 large eggs.", "Slice the medium onion.", "Slice the onion."],
      expected: [[0], [1], [1]]
    ),

  ]

  @Test(arguments: cases)
  func matchesTheReference(_ c: BrewingCase) {
    #expect(c.result == c.expected)
  }
}
