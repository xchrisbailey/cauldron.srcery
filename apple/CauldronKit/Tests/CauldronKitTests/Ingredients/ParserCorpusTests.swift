import CauldronKit
import Testing

/// Ported case for case from `packages/shared/test/ingredients/corpus.test.ts`.
struct CorpusCase: Sendable, CustomTestStringConvertible {
  let line: String
  let expected: ParsedIngredient

  var testDescription: String { line.debugDescription }
}

private func quantity(_ q: [Double]?) -> Quantity? {
  q.map { Quantity(min: $0[0], max: $0.count > 1 ? $0[1] : nil) }
}

func corpusCase(
  _ line: String, q: [Double]? = nil, u: UnitCode? = nil, item: String, note: String? = nil,
  optional: Bool = false, alt: ([Double], UnitCode)? = nil
) -> CorpusCase {
  CorpusCase(
    line: line,
    expected: ParsedIngredient(
      quantity: quantity(q), unit: u, item: item, note: note, optional: optional,
      alt: alt.flatMap { measure in
        quantity(measure.0).map { AltMeasure(quantity: $0, unit: measure.1) }
      },
      original: line))
}

let corpus: [CorpusCase] = [
  // integers and plain units
  corpusCase("2 cups flour", q: [2], u: .cup, item: "flour"),
  corpusCase("1 cup sugar", q: [1], u: .cup, item: "sugar"),
  corpusCase("3 tablespoons olive oil", q: [3], u: .tbsp, item: "olive oil"),
  corpusCase("1 teaspoon vanilla extract", q: [1], u: .tsp, item: "vanilla extract"),
  corpusCase("4 cups chicken broth", q: [4], u: .cup, item: "chicken broth"),
  corpusCase("12 ounces pasta", q: [12], u: .oz, item: "pasta"),
  corpusCase("1 pound ground beef", q: [1], u: .lb, item: "ground beef"),
  corpusCase("2 quarts water", q: [2], u: .quart, item: "water"),
  corpusCase("1 gallon milk", q: [1], u: .gallon, item: "milk"),
  corpusCase("1 pint cherry tomatoes", q: [1], u: .pint, item: "cherry tomatoes"),
  corpusCase("2 pints blueberries", q: [2], u: .pint, item: "blueberries"),
  corpusCase("500 ml stock", q: [500], u: .ml, item: "stock"),
  corpusCase("1 liter water", q: [1], u: .l, item: "water"),
  corpusCase("2 litres milk", q: [2], u: .l, item: "milk"),
  corpusCase("250 grams butter", q: [250], u: .g, item: "butter"),
  corpusCase("1 kg potatoes", q: [1], u: .kg, item: "potatoes"),
  corpusCase("2 kilograms beef brisket", q: [2], u: .kg, item: "beef brisket"),
  corpusCase("8 fl oz heavy cream", q: [8], u: .flOz, item: "heavy cream"),
  corpusCase("8 fl. oz. buttermilk", q: [8], u: .flOz, item: "buttermilk"),
  corpusCase("4 fluid ounces lemon juice", q: [4], u: .flOz, item: "lemon juice"),
  // unit aliases: abbreviations, dots, plurals, case
  corpusCase("2 tsp baking powder", q: [2], u: .tsp, item: "baking powder"),
  corpusCase("2 tsp. baking soda", q: [2], u: .tsp, item: "baking soda"),
  corpusCase("2 tsps salt", q: [2], u: .tsp, item: "salt"),
  corpusCase("1 Tbsp. soy sauce", q: [1], u: .tbsp, item: "soy sauce"),
  corpusCase("2 tbsp butter", q: [2], u: .tbsp, item: "butter"),
  corpusCase("2 TBSP honey", q: [2], u: .tbsp, item: "honey"),
  corpusCase("2 T olive oil", q: [2], u: .tbsp, item: "olive oil"),
  corpusCase("1 t salt", q: [1], u: .tsp, item: "salt"),
  corpusCase("1 T. sugar", q: [1], u: .tbsp, item: "sugar"),
  corpusCase("3 c. flour", q: [3], u: .cup, item: "flour"),
  corpusCase("1 C sugar", q: [1], u: .cup, item: "sugar"),
  corpusCase("2 lbs potatoes", q: [2], u: .lb, item: "potatoes"),
  corpusCase("3 lb. carrots", q: [3], u: .lb, item: "carrots"),
  corpusCase("8 oz. cream cheese", q: [8], u: .oz, item: "cream cheese"),
  corpusCase("8 oz cheddar", q: [8], u: .oz, item: "cheddar"),
  corpusCase("100 g dark chocolate", q: [100], u: .g, item: "dark chocolate"),
  corpusCase("100g dark chocolate", q: [100], u: .g, item: "dark chocolate"),
  corpusCase("250ml cream", q: [250], u: .ml, item: "cream"),
  corpusCase("1.5kg chicken", q: [1.5], u: .kg, item: "chicken"),
  corpusCase("2tbsp oil", q: [2], u: .tbsp, item: "oil"),
  corpusCase("2 Tablespoons flour", q: [2], u: .tbsp, item: "flour"),
  corpusCase("2 qt. stock", q: [2], u: .quart, item: "stock"),
  corpusCase("1 gal water", q: [1], u: .gallon, item: "water"),
  corpusCase("400 mL coconut milk", q: [400], u: .ml, item: "coconut milk"),
  corpusCase("2 L soda water", q: [2], u: .l, item: "soda water"),
  corpusCase("3 grams saffron", q: [3], u: .g, item: "saffron"),
  corpusCase("2 cups of flour", q: [2], u: .cup, item: "flour"),
  // decimals
  corpusCase("1.5 cups milk", q: [1.5], u: .cup, item: "milk"),
  corpusCase("0.25 tsp nutmeg", q: [0.25], u: .tsp, item: "nutmeg"),
  corpusCase(".5 cup raisins", q: [0.5], u: .cup, item: "raisins"),
  corpusCase("2.5 kg flour", q: [2.5], u: .kg, item: "flour"),
  // fractions and mixed numbers
  corpusCase("3/4 cup sugar", q: [0.75], u: .cup, item: "sugar"),
  corpusCase("1/2 teaspoon salt", q: [0.5], u: .tsp, item: "salt"),
  corpusCase("1/3 cup honey", q: [0.3333333333333333], u: .cup, item: "honey"),
  corpusCase("1 1/2 cups flour", q: [1.5], u: .cup, item: "flour"),
  corpusCase("2 3/4 cups milk", q: [2.75], u: .cup, item: "milk"),
  corpusCase("1-1/2 cups sugar", q: [1.5], u: .cup, item: "sugar"),
  corpusCase("1/8 tsp cloves", q: [0.125], u: .tsp, item: "cloves"),
  corpusCase("10 1/2 oz noodles", q: [10.5], u: .oz, item: "noodles"),
  // unicode fractions
  corpusCase("½ cup butter", q: [0.5], u: .cup, item: "butter"),
  corpusCase("½ tsp. kosher salt", q: [0.5], u: .tsp, item: "kosher salt"),
  corpusCase("1½ cups sugar", q: [1.5], u: .cup, item: "sugar"),
  corpusCase("1 ½ cups sugar", q: [1.5], u: .cup, item: "sugar"),
  corpusCase("⅓ cup olive oil", q: [0.3333333333333333], u: .cup, item: "olive oil"),
  corpusCase("2⅔ cups flour", q: [2.6666666666666665], u: .cup, item: "flour"),
  corpusCase("¼ teaspoon pepper", q: [0.25], u: .tsp, item: "pepper"),
  corpusCase("¾ cup oats", q: [0.75], u: .cup, item: "oats"),
  corpusCase("⅛ tsp cayenne", q: [0.125], u: .tsp, item: "cayenne"),
  corpusCase("½tsp cumin", q: [0.5], u: .tsp, item: "cumin"),
  corpusCase("1 ¼ lb pork shoulder", q: [1.25], u: .lb, item: "pork shoulder"),
  // ranges
  corpusCase("2-3 cloves garlic, minced", q: [2, 3], u: .clove, item: "garlic", note: "minced"),
  corpusCase("2–3 cloves garlic, minced", q: [2, 3], u: .clove, item: "garlic", note: "minced"),
  corpusCase("2 to 3 tablespoons butter", q: [2, 3], u: .tbsp, item: "butter"),
  corpusCase("2 - 3 tbsp lemon juice", q: [2, 3], u: .tbsp, item: "lemon juice"),
  corpusCase("1/2-1 cup water", q: [0.5, 1], u: .cup, item: "water"),
  corpusCase("1 to 1 1/2 cups broth", q: [1, 1.5], u: .cup, item: "broth"),
  corpusCase("350-400 g flour", q: [350, 400], u: .g, item: "flour"),
  corpusCase("3—4 sprigs thyme", q: [3, 4], u: .sprig, item: "thyme"),
  corpusCase("two to three tablespoons oil", q: [2, 3], u: .tbsp, item: "oil"),
  corpusCase("½–1 tsp chili flakes", q: [0.5, 1], u: .tsp, item: "chili flakes"),
  // number words
  corpusCase("a pinch of salt", q: [1], u: .pinch, item: "salt"),
  corpusCase("A pinch nutmeg", q: [1], u: .pinch, item: "nutmeg"),
  corpusCase("an onion, diced", q: [1], item: "onion", note: "diced"),
  corpusCase("one lemon", q: [1], item: "lemon"),
  corpusCase(
    "One 14-ounce can coconut milk", q: [1], u: .can, item: "coconut milk", alt: ([14], .oz)),
  corpusCase("two eggs", q: [2], item: "eggs"),
  corpusCase("three cloves garlic", q: [3], u: .clove, item: "garlic"),
  corpusCase("a dash of hot sauce", q: [1], u: .dash, item: "hot sauce"),
  corpusCase("a few sprigs parsley", item: "a few sprigs parsley"),
  // sizes stay in the item
  corpusCase("2 large eggs", q: [2], item: "large eggs"),
  corpusCase(
    "3 large eggs, at room temperature", q: [3], item: "large eggs", note: "at room temperature"),
  corpusCase("1 medium onion, chopped", q: [1], item: "medium onion", note: "chopped"),
  corpusCase(
    "2 small shallots, thinly sliced", q: [2], item: "small shallots", note: "thinly sliced"),
  corpusCase("1 large lemon", q: [1], item: "large lemon"),
  corpusCase("4 medium tomatoes, diced", q: [4], item: "medium tomatoes", note: "diced"),
  corpusCase("2 jumbo egg yolks", q: [2], item: "jumbo egg yolks"),
  // count units
  corpusCase("3 cloves garlic", q: [3], u: .clove, item: "garlic"),
  corpusCase("1 can black beans, drained", q: [1], u: .can, item: "black beans", note: "drained"),
  corpusCase("2 cans chickpeas", q: [2], u: .can, item: "chickpeas"),
  corpusCase("2 slices bacon", q: [2], u: .slice, item: "bacon"),
  corpusCase("1 bunch cilantro", q: [1], u: .bunch, item: "cilantro"),
  corpusCase("2 bunches kale", q: [2], u: .bunch, item: "kale"),
  corpusCase("4 sprigs thyme", q: [4], u: .sprig, item: "thyme"),
  corpusCase("1 stick butter", q: [1], u: .stick, item: "butter"),
  corpusCase(
    "2 sticks unsalted butter, softened", q: [2], u: .stick, item: "unsalted butter",
    note: "softened"),
  corpusCase("1 piece ginger", q: [1], u: .piece, item: "ginger"),
  corpusCase("1 package cream cheese", q: [1], u: .package, item: "cream cheese"),
  corpusCase("2 pkg yeast", q: [2], u: .package, item: "yeast"),
  // parenthetical alternate measures
  corpusCase(
    "1 1/2 cups (190g) flour, sifted", q: [1.5], u: .cup, item: "flour", note: "sifted",
    alt: ([190], .g)),
  corpusCase("1 cup (240 ml) milk", q: [1], u: .cup, item: "milk", alt: ([240], .ml)),
  corpusCase(
    "2 cups (250g) all-purpose flour", q: [2], u: .cup, item: "all-purpose flour", alt: ([250], .g)),
  corpusCase("1 stick (113 g) butter", q: [1], u: .stick, item: "butter", alt: ([113], .g)),
  corpusCase("1 (14 oz) can tomatoes", q: [1], u: .can, item: "tomatoes", alt: ([14], .oz)),
  corpusCase(
    "1 (28-ounce) can crushed tomatoes", q: [1], u: .can, item: "crushed tomatoes", alt: ([28], .oz)
  ),
  corpusCase(
    "2 (15-oz) cans chickpeas, drained", q: [2], u: .can, item: "chickpeas", note: "drained",
    alt: ([15], .oz)),
  corpusCase(
    "1 14-ounce can coconut milk", q: [1], u: .can, item: "coconut milk", alt: ([14], .oz)),
  corpusCase("10 oz spinach (about 8 cups)", q: [10], u: .oz, item: "spinach", alt: ([8], .cup)),
  corpusCase("1 cup (packed) brown sugar", q: [1], u: .cup, item: "brown sugar", note: "packed"),
  corpusCase(
    "3 tablespoons (45g) butter, melted", q: [3], u: .tbsp, item: "butter", note: "melted",
    alt: ([45], .g)),
  corpusCase("1 cup (8 fl oz) cream", q: [1], u: .cup, item: "cream", alt: ([8], .flOz)),
  corpusCase("1/2 cup (about 60 g) walnuts", q: [0.5], u: .cup, item: "walnuts", alt: ([60], .g)),
  corpusCase(
    "1 large (about 200 g) sweet potato", q: [1], item: "large sweet potato", alt: ([200], .g)),
  // "plus"
  corpusCase(
    "1 cup plus 2 tablespoons milk", q: [1], u: .cup, item: "milk", note: "plus 2 tablespoons"),
  corpusCase(
    "2 tablespoons plus 1 teaspoon sugar", q: [2], u: .tbsp, item: "sugar", note: "plus 1 teaspoon"),
  corpusCase(
    "1/2 cup plus 1 tbsp flour, sifted", q: [0.5], u: .cup, item: "flour",
    note: "plus 1 tbsp, sifted"),
  corpusCase("1 cup + 2 tbsp water", q: [1], u: .cup, item: "water", note: "+ 2 tbsp"),
  // notes and optional
  corpusCase(
    "2 lbs. chicken thighs, bone-in", q: [2], u: .lb, item: "chicken thighs", note: "bone-in"),
  corpusCase(
    "1/4 teaspoon cayenne pepper (optional)", q: [0.25], u: .tsp, item: "cayenne pepper",
    optional: true),
  corpusCase(
    "1 cup walnuts, chopped (optional)", q: [1], u: .cup, item: "walnuts", note: "chopped",
    optional: true),
  corpusCase("1 cup walnuts, optional", q: [1], u: .cup, item: "walnuts", optional: true),
  corpusCase(
    "2 tbsp parsley, finely chopped", q: [2], u: .tbsp, item: "parsley", note: "finely chopped"),
  corpusCase("1 onion, finely chopped", q: [1], item: "onion", note: "finely chopped"),
  corpusCase(
    "1 cup butter, softened, plus more for greasing", q: [1], u: .cup, item: "butter",
    note: "softened, plus more for greasing"),
  corpusCase("3 tbsp olive oil, divided", q: [3], u: .tbsp, item: "olive oil", note: "divided"),
  corpusCase("2 tbsp olive oil divided", q: [2], u: .tbsp, item: "olive oil", note: "divided"),
  corpusCase("1 cup parmesan for serving", q: [1], u: .cup, item: "parmesan", note: "for serving"),
  corpusCase("2 tbsp chives for garnish", q: [2], u: .tbsp, item: "chives", note: "for garnish"),
  corpusCase(
    "1 (8 oz) package cream cheese, at room temperature", q: [1], u: .package, item: "cream cheese",
    note: "at room temperature", alt: ([8], .oz)),
  // no quantity
  corpusCase("Salt, to taste", item: "Salt", note: "to taste"),
  corpusCase("salt and pepper, to taste", item: "salt and pepper", note: "to taste"),
  corpusCase("Salt and pepper to taste", item: "Salt and pepper", note: "to taste"),
  corpusCase("Kosher salt", item: "Kosher salt"),
  corpusCase("Freshly ground black pepper", item: "Freshly ground black pepper"),
  corpusCase("Juice of 1 lemon", item: "Juice of 1 lemon"),
  corpusCase("Zest of 2 limes", item: "Zest of 2 limes"),
  corpusCase("Olive oil, for frying", item: "Olive oil", note: "for frying"),
  corpusCase("Cooking spray", item: "Cooking spray"),
  corpusCase("Pinch of salt", item: "Pinch of salt"),
  corpusCase("Fresh basil leaves, to garnish", item: "Fresh basil leaves", note: "to garnish"),
  // bullets and whitespace
  corpusCase("- 2 cups flour", q: [2], u: .cup, item: "flour"),
  corpusCase("• 1 tsp salt", q: [1], u: .tsp, item: "salt"),
  corpusCase("* 3 eggs", q: [3], item: "eggs"),
  corpusCase("•1 cup sugar", q: [1], u: .cup, item: "sugar"),
  corpusCase("  2   cups   flour  ", q: [2], u: .cup, item: "flour"),
  corpusCase("\t1 tbsp butter\n", q: [1], u: .tbsp, item: "butter"),
  corpusCase("2 cups flour ,  sifted", q: [2], u: .cup, item: "flour", note: "sifted"),
  // odd but real
  corpusCase(
    "2 tablespoons extra-virgin olive oil", q: [2], u: .tbsp, item: "extra-virgin olive oil"),
  corpusCase("1 1/2-inch piece ginger, peeled", item: "1 1/2-inch piece ginger", note: "peeled"),
  corpusCase("5-minute sauce", item: "5-minute sauce"),
  corpusCase("1. Mix the flour", item: "1. Mix the flour"),
  corpusCase("2 cups", item: "cups"),
  corpusCase("3 cloves", item: "cloves"),
  corpusCase("2 eggs or 1/2 cup applesauce", q: [2], item: "eggs or 1/2 cup applesauce"),
  corpusCase("1 cup milk or cream", q: [1], u: .cup, item: "milk or cream"),
  corpusCase(
    "1 cup sour cream (or plain yogurt)", q: [1], u: .cup, item: "sour cream",
    note: "or plain yogurt"),
  corpusCase(
    "1 cup tomatoes (diced, drained)", q: [1], u: .cup, item: "tomatoes", note: "diced, drained"),
  corpusCase("16 oz. canned pumpkin purée", q: [16], u: .oz, item: "canned pumpkin purée"),
  corpusCase(
    "6 tbsp. unsalted butter, cubed", q: [6], u: .tbsp, item: "unsalted butter", note: "cubed"),
  // thousands separators
  corpusCase("1,000 g flour", q: [1000], u: .g, item: "flour"),
  corpusCase("1,500 ml stock", q: [1500], u: .ml, item: "stock"),
  corpusCase("2,500.5 g sugar", q: [2500.5], u: .g, item: "sugar"),
  // slash alternate measures
  corpusCase("400g/14oz tin tomatoes", q: [400], u: .g, item: "tin tomatoes", alt: ([14], .oz)),
  corpusCase("1 cup / 240 ml milk", q: [1], u: .cup, item: "milk", alt: ([240], .ml)),
  corpusCase("400g/14oz can tomatoes", q: [400], u: .g, item: "can tomatoes", alt: ([14], .oz)),
  // count x size
  corpusCase("2 x 400g cans chickpeas", q: [2], u: .can, item: "chickpeas", alt: ([400], .g)),
  corpusCase(
    "2 x 400g cans chickpeas, drained", q: [2], u: .can, item: "chickpeas", note: "drained",
    alt: ([400], .g)),
  // fill modifiers go to the note
  corpusCase("1 heaping tsp salt", q: [1], u: .tsp, item: "salt", note: "heaping"),
  corpusCase("2 heaped tbsp sugar", q: [2], u: .tbsp, item: "sugar", note: "heaped"),
  corpusCase("1 level tablespoon flour", q: [1], u: .tbsp, item: "flour", note: "level"),
  corpusCase("1 scant cup milk", q: [1], u: .cup, item: "milk", note: "scant"),
  corpusCase(
    "1 rounded teaspoon baking powder", q: [1], u: .tsp, item: "baking powder", note: "rounded"),
  corpusCase("a heaping teaspoon salt", q: [1], u: .tsp, item: "salt", note: "heaping"),
  // half and articles after a quantity
  corpusCase("half an onion", q: [0.5], item: "onion"),
  corpusCase("1/2 an onion", q: [0.5], item: "onion"),
  corpusCase("half a lemon", q: [0.5], item: "lemon"),
  corpusCase("1/2 a cup flour", q: [0.5], u: .cup, item: "flour"),
  corpusCase("half and half", item: "half and half"),
  // dozen is a multiplier
  corpusCase("2 dozen eggs", q: [24], item: "eggs"),
  corpusCase("a dozen eggs", q: [12], item: "eggs"),
  corpusCase("half a dozen eggs", q: [6], item: "eggs"),
  // glued and short units
  corpusCase("1 tsp.salt", q: [1], u: .tsp, item: "salt"),
  corpusCase("1 ts salt", q: [1], u: .tsp, item: "salt"),
  // each after a unit
  corpusCase(
    "2 tbsp each salt and pepper", q: [2], u: .tbsp, item: "salt and pepper", note: "each"),
  // weight then container word: weight is the measure, the container stays in the item
  corpusCase("12 oz. package spaghetti", q: [12], u: .oz, item: "package spaghetti"),
  corpusCase("1/0 cup mystery", item: "1/0 cup mystery"),
  corpusCase("", item: ""),
  corpusCase("   ", item: ""),
]

@Suite("Ingredient corpus")
struct IngredientCorpusTests {
  @Test func hasAtLeast120Lines() {
    #expect(corpus.count >= 120)
  }

  @Test(arguments: corpus)
  func parsesTheLine(_ c: CorpusCase) {
    #expect(parseIngredientLine(c.line) == c.expected)
  }
}

@Suite("parseIngredientLine robustness")
struct ParserRobustnessTests {
  @Test func neverTrapsAndAlwaysEchoesTheInput() {
    let weird = [
      "(", ")", "((", "1/", "/2", "1 -", "- -", "½", "1 (", "(optional)", ",", ", ,", "1 to",
      "to 2",
    ]
    for line in weird {
      #expect(parseIngredientLine(line).original == line)
    }
  }

  @Test func isDeterministic() {
    let a = parseIngredientLine("1 1/2 cups (190g) flour, sifted")
    let b = parseIngredientLine("1 1/2 cups (190g) flour, sifted")
    #expect(a == b)
  }
}

@Suite("isSectionHeading")
struct IsSectionHeadingTests {
  @Test(
    arguments: [
      ("For the sauce:", true),
      ("For the crust", true),
      ("Dressing:", true),
      ("- FOR THE FILLING", true),
      ("2 cups flour", false),
      ("Salt, to taste", false),
      ("Kosher salt", false),
      ("", false),
    ])
  func readsHeadings(line: String, expected: Bool) {
    #expect(isSectionHeading(line) == expected)
  }
}
