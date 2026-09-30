import { describe, expect, it } from "vite-plus/test";
import {
  isSectionHeading,
  parseIngredientLine,
  type ParsedIngredient,
  type UnitCode,
} from "../../src/index.ts";

type Q = readonly [min: number, max?: number];
interface Expect {
  q?: Q;
  u?: UnitCode;
  item: string;
  note?: string;
  optional?: boolean;
  alt?: readonly [Q, UnitCode];
}

const toQuantity = (q: Q | undefined) => (q ? { min: q[0], max: q[1] ?? null } : null);

function full(line: string, e: Expect): ParsedIngredient {
  return {
    quantity: toQuantity(e.q),
    unit: e.u ?? null,
    item: e.item,
    note: e.note ?? null,
    optional: e.optional ?? false,
    alt: e.alt ? { quantity: toQuantity(e.alt[0])!, unit: e.alt[1] } : null,
    original: line,
  };
}

const corpus: readonly (readonly [string, Expect])[] = [
  // integers and plain units
  ["2 cups flour", { q: [2], u: "cup", item: "flour" }],
  ["1 cup sugar", { q: [1], u: "cup", item: "sugar" }],
  ["3 tablespoons olive oil", { q: [3], u: "tbsp", item: "olive oil" }],
  ["1 teaspoon vanilla extract", { q: [1], u: "tsp", item: "vanilla extract" }],
  ["4 cups chicken broth", { q: [4], u: "cup", item: "chicken broth" }],
  ["12 ounces pasta", { q: [12], u: "oz", item: "pasta" }],
  ["1 pound ground beef", { q: [1], u: "lb", item: "ground beef" }],
  ["2 quarts water", { q: [2], u: "quart", item: "water" }],
  ["1 gallon milk", { q: [1], u: "gallon", item: "milk" }],
  ["1 pint cherry tomatoes", { q: [1], u: "pint", item: "cherry tomatoes" }],
  ["2 pints blueberries", { q: [2], u: "pint", item: "blueberries" }],
  ["500 ml stock", { q: [500], u: "ml", item: "stock" }],
  ["1 liter water", { q: [1], u: "l", item: "water" }],
  ["2 litres milk", { q: [2], u: "l", item: "milk" }],
  ["250 grams butter", { q: [250], u: "g", item: "butter" }],
  ["1 kg potatoes", { q: [1], u: "kg", item: "potatoes" }],
  ["2 kilograms beef brisket", { q: [2], u: "kg", item: "beef brisket" }],
  ["8 fl oz heavy cream", { q: [8], u: "fl_oz", item: "heavy cream" }],
  ["8 fl. oz. buttermilk", { q: [8], u: "fl_oz", item: "buttermilk" }],
  ["4 fluid ounces lemon juice", { q: [4], u: "fl_oz", item: "lemon juice" }],

  // unit aliases: abbreviations, dots, plurals, case
  ["2 tsp baking powder", { q: [2], u: "tsp", item: "baking powder" }],
  ["2 tsp. baking soda", { q: [2], u: "tsp", item: "baking soda" }],
  ["2 tsps salt", { q: [2], u: "tsp", item: "salt" }],
  ["1 Tbsp. soy sauce", { q: [1], u: "tbsp", item: "soy sauce" }],
  ["2 tbsp butter", { q: [2], u: "tbsp", item: "butter" }],
  ["2 TBSP honey", { q: [2], u: "tbsp", item: "honey" }],
  ["2 T olive oil", { q: [2], u: "tbsp", item: "olive oil" }],
  ["1 t salt", { q: [1], u: "tsp", item: "salt" }],
  ["1 T. sugar", { q: [1], u: "tbsp", item: "sugar" }],
  ["3 c. flour", { q: [3], u: "cup", item: "flour" }],
  ["1 C sugar", { q: [1], u: "cup", item: "sugar" }],
  ["2 lbs potatoes", { q: [2], u: "lb", item: "potatoes" }],
  ["3 lb. carrots", { q: [3], u: "lb", item: "carrots" }],
  ["8 oz. cream cheese", { q: [8], u: "oz", item: "cream cheese" }],
  ["8 oz cheddar", { q: [8], u: "oz", item: "cheddar" }],
  ["100 g dark chocolate", { q: [100], u: "g", item: "dark chocolate" }],
  ["100g dark chocolate", { q: [100], u: "g", item: "dark chocolate" }],
  ["250ml cream", { q: [250], u: "ml", item: "cream" }],
  ["1.5kg chicken", { q: [1.5], u: "kg", item: "chicken" }],
  ["2tbsp oil", { q: [2], u: "tbsp", item: "oil" }],
  ["2 Tablespoons flour", { q: [2], u: "tbsp", item: "flour" }],
  ["2 qt. stock", { q: [2], u: "quart", item: "stock" }],
  ["1 gal water", { q: [1], u: "gallon", item: "water" }],
  ["400 mL coconut milk", { q: [400], u: "ml", item: "coconut milk" }],
  ["2 L soda water", { q: [2], u: "l", item: "soda water" }],
  ["3 grams saffron", { q: [3], u: "g", item: "saffron" }],
  ["2 cups of flour", { q: [2], u: "cup", item: "flour" }],

  // decimals
  ["1.5 cups milk", { q: [1.5], u: "cup", item: "milk" }],
  ["0.25 tsp nutmeg", { q: [0.25], u: "tsp", item: "nutmeg" }],
  [".5 cup raisins", { q: [0.5], u: "cup", item: "raisins" }],
  ["2.5 kg flour", { q: [2.5], u: "kg", item: "flour" }],

  // fractions and mixed numbers
  ["3/4 cup sugar", { q: [0.75], u: "cup", item: "sugar" }],
  ["1/2 teaspoon salt", { q: [0.5], u: "tsp", item: "salt" }],
  ["1/3 cup honey", { q: [1 / 3], u: "cup", item: "honey" }],
  ["1 1/2 cups flour", { q: [1.5], u: "cup", item: "flour" }],
  ["2 3/4 cups milk", { q: [2.75], u: "cup", item: "milk" }],
  ["1-1/2 cups sugar", { q: [1.5], u: "cup", item: "sugar" }],
  ["1/8 tsp cloves", { q: [0.125], u: "tsp", item: "cloves" }],
  ["10 1/2 oz noodles", { q: [10.5], u: "oz", item: "noodles" }],

  // unicode fractions
  ["½ cup butter", { q: [0.5], u: "cup", item: "butter" }],
  ["½ tsp. kosher salt", { q: [0.5], u: "tsp", item: "kosher salt" }],
  ["1½ cups sugar", { q: [1.5], u: "cup", item: "sugar" }],
  ["1 ½ cups sugar", { q: [1.5], u: "cup", item: "sugar" }],
  ["⅓ cup olive oil", { q: [1 / 3], u: "cup", item: "olive oil" }],
  ["2⅔ cups flour", { q: [2 + 2 / 3], u: "cup", item: "flour" }],
  ["¼ teaspoon pepper", { q: [0.25], u: "tsp", item: "pepper" }],
  ["¾ cup oats", { q: [0.75], u: "cup", item: "oats" }],
  ["⅛ tsp cayenne", { q: [0.125], u: "tsp", item: "cayenne" }],
  ["½tsp cumin", { q: [0.5], u: "tsp", item: "cumin" }],
  ["1 ¼ lb pork shoulder", { q: [1.25], u: "lb", item: "pork shoulder" }],

  // ranges
  ["2-3 cloves garlic, minced", { q: [2, 3], u: "clove", item: "garlic", note: "minced" }],
  ["2–3 cloves garlic, minced", { q: [2, 3], u: "clove", item: "garlic", note: "minced" }],
  ["2 to 3 tablespoons butter", { q: [2, 3], u: "tbsp", item: "butter" }],
  ["2 - 3 tbsp lemon juice", { q: [2, 3], u: "tbsp", item: "lemon juice" }],
  ["1/2-1 cup water", { q: [0.5, 1], u: "cup", item: "water" }],
  ["1 to 1 1/2 cups broth", { q: [1, 1.5], u: "cup", item: "broth" }],
  ["350-400 g flour", { q: [350, 400], u: "g", item: "flour" }],
  ["3—4 sprigs thyme", { q: [3, 4], u: "sprig", item: "thyme" }],
  ["two to three tablespoons oil", { q: [2, 3], u: "tbsp", item: "oil" }],
  ["½–1 tsp chili flakes", { q: [0.5, 1], u: "tsp", item: "chili flakes" }],

  // number words
  ["a pinch of salt", { q: [1], u: "pinch", item: "salt" }],
  ["A pinch nutmeg", { q: [1], u: "pinch", item: "nutmeg" }],
  ["an onion, diced", { q: [1], item: "onion", note: "diced" }],
  ["one lemon", { q: [1], item: "lemon" }],
  ["One 14-ounce can coconut milk", { q: [1], u: "can", item: "coconut milk", alt: [[14], "oz"] }],
  ["two eggs", { q: [2], item: "eggs" }],
  ["three cloves garlic", { q: [3], u: "clove", item: "garlic" }],
  ["a dash of hot sauce", { q: [1], u: "dash", item: "hot sauce" }],
  ["a few sprigs parsley", { item: "a few sprigs parsley" }],

  // sizes stay in the item
  ["2 large eggs", { q: [2], item: "large eggs" }],
  [
    "3 large eggs, at room temperature",
    { q: [3], item: "large eggs", note: "at room temperature" },
  ],
  ["1 medium onion, chopped", { q: [1], item: "medium onion", note: "chopped" }],
  ["2 small shallots, thinly sliced", { q: [2], item: "small shallots", note: "thinly sliced" }],
  ["1 large lemon", { q: [1], item: "large lemon" }],
  ["4 medium tomatoes, diced", { q: [4], item: "medium tomatoes", note: "diced" }],
  ["2 jumbo egg yolks", { q: [2], item: "jumbo egg yolks" }],

  // count units
  ["3 cloves garlic", { q: [3], u: "clove", item: "garlic" }],
  ["1 can black beans, drained", { q: [1], u: "can", item: "black beans", note: "drained" }],
  ["2 cans chickpeas", { q: [2], u: "can", item: "chickpeas" }],
  ["2 slices bacon", { q: [2], u: "slice", item: "bacon" }],
  ["1 bunch cilantro", { q: [1], u: "bunch", item: "cilantro" }],
  ["2 bunches kale", { q: [2], u: "bunch", item: "kale" }],
  ["4 sprigs thyme", { q: [4], u: "sprig", item: "thyme" }],
  ["1 stick butter", { q: [1], u: "stick", item: "butter" }],
  [
    "2 sticks unsalted butter, softened",
    { q: [2], u: "stick", item: "unsalted butter", note: "softened" },
  ],
  ["1 piece ginger", { q: [1], u: "piece", item: "ginger" }],
  ["1 package cream cheese", { q: [1], u: "package", item: "cream cheese" }],
  ["2 pkg yeast", { q: [2], u: "package", item: "yeast" }],

  // parenthetical alternate measures
  [
    "1 1/2 cups (190g) flour, sifted",
    { q: [1.5], u: "cup", item: "flour", note: "sifted", alt: [[190], "g"] },
  ],
  ["1 cup (240 ml) milk", { q: [1], u: "cup", item: "milk", alt: [[240], "ml"] }],
  [
    "2 cups (250g) all-purpose flour",
    { q: [2], u: "cup", item: "all-purpose flour", alt: [[250], "g"] },
  ],
  ["1 stick (113 g) butter", { q: [1], u: "stick", item: "butter", alt: [[113], "g"] }],
  ["1 (14 oz) can tomatoes", { q: [1], u: "can", item: "tomatoes", alt: [[14], "oz"] }],
  [
    "1 (28-ounce) can crushed tomatoes",
    { q: [1], u: "can", item: "crushed tomatoes", alt: [[28], "oz"] },
  ],
  [
    "2 (15-oz) cans chickpeas, drained",
    { q: [2], u: "can", item: "chickpeas", note: "drained", alt: [[15], "oz"] },
  ],
  ["1 14-ounce can coconut milk", { q: [1], u: "can", item: "coconut milk", alt: [[14], "oz"] }],
  ["10 oz spinach (about 8 cups)", { q: [10], u: "oz", item: "spinach", alt: [[8], "cup"] }],
  ["1 cup (packed) brown sugar", { q: [1], u: "cup", item: "brown sugar", note: "packed" }],
  [
    "3 tablespoons (45g) butter, melted",
    { q: [3], u: "tbsp", item: "butter", note: "melted", alt: [[45], "g"] },
  ],
  ["1 cup (8 fl oz) cream", { q: [1], u: "cup", item: "cream", alt: [[8], "fl_oz"] }],
  ["1/2 cup (about 60 g) walnuts", { q: [0.5], u: "cup", item: "walnuts", alt: [[60], "g"] }],
  ["1 large (about 200 g) sweet potato", { q: [1], item: "large sweet potato", alt: [[200], "g"] }],

  // "plus"
  ["1 cup plus 2 tablespoons milk", { q: [1], u: "cup", item: "milk", note: "plus 2 tablespoons" }],
  [
    "2 tablespoons plus 1 teaspoon sugar",
    { q: [2], u: "tbsp", item: "sugar", note: "plus 1 teaspoon" },
  ],
  [
    "1/2 cup plus 1 tbsp flour, sifted",
    { q: [0.5], u: "cup", item: "flour", note: "plus 1 tbsp, sifted" },
  ],
  ["1 cup + 2 tbsp water", { q: [1], u: "cup", item: "water", note: "+ 2 tbsp" }],

  // notes and optional
  ["2 lbs. chicken thighs, bone-in", { q: [2], u: "lb", item: "chicken thighs", note: "bone-in" }],
  [
    "1/4 teaspoon cayenne pepper (optional)",
    { q: [0.25], u: "tsp", item: "cayenne pepper", optional: true },
  ],
  [
    "1 cup walnuts, chopped (optional)",
    { q: [1], u: "cup", item: "walnuts", note: "chopped", optional: true },
  ],
  ["1 cup walnuts, optional", { q: [1], u: "cup", item: "walnuts", optional: true }],
  [
    "2 tbsp parsley, finely chopped",
    { q: [2], u: "tbsp", item: "parsley", note: "finely chopped" },
  ],
  ["1 onion, finely chopped", { q: [1], item: "onion", note: "finely chopped" }],
  [
    "1 cup butter, softened, plus more for greasing",
    { q: [1], u: "cup", item: "butter", note: "softened, plus more for greasing" },
  ],
  ["3 tbsp olive oil, divided", { q: [3], u: "tbsp", item: "olive oil", note: "divided" }],
  ["2 tbsp olive oil divided", { q: [2], u: "tbsp", item: "olive oil", note: "divided" }],
  ["1 cup parmesan for serving", { q: [1], u: "cup", item: "parmesan", note: "for serving" }],
  ["2 tbsp chives for garnish", { q: [2], u: "tbsp", item: "chives", note: "for garnish" }],
  [
    "1 (8 oz) package cream cheese, at room temperature",
    { q: [1], u: "package", item: "cream cheese", note: "at room temperature", alt: [[8], "oz"] },
  ],

  // no quantity
  ["Salt, to taste", { item: "Salt", note: "to taste" }],
  ["salt and pepper, to taste", { item: "salt and pepper", note: "to taste" }],
  ["Salt and pepper to taste", { item: "Salt and pepper", note: "to taste" }],
  ["Kosher salt", { item: "Kosher salt" }],
  ["Freshly ground black pepper", { item: "Freshly ground black pepper" }],
  ["Juice of 1 lemon", { item: "Juice of 1 lemon" }],
  ["Zest of 2 limes", { item: "Zest of 2 limes" }],
  ["Olive oil, for frying", { item: "Olive oil", note: "for frying" }],
  ["Cooking spray", { item: "Cooking spray" }],
  ["Pinch of salt", { item: "Pinch of salt" }],
  ["Fresh basil leaves, to garnish", { item: "Fresh basil leaves", note: "to garnish" }],

  // bullets and whitespace
  ["- 2 cups flour", { q: [2], u: "cup", item: "flour" }],
  ["• 1 tsp salt", { q: [1], u: "tsp", item: "salt" }],
  ["* 3 eggs", { q: [3], item: "eggs" }],
  ["•1 cup sugar", { q: [1], u: "cup", item: "sugar" }],
  ["  2   cups   flour  ", { q: [2], u: "cup", item: "flour" }],
  ["\t1 tbsp butter\n", { q: [1], u: "tbsp", item: "butter" }],
  ["2 cups flour ,  sifted", { q: [2], u: "cup", item: "flour", note: "sifted" }],

  // odd but real
  ["2 tablespoons extra-virgin olive oil", { q: [2], u: "tbsp", item: "extra-virgin olive oil" }],
  ["1 1/2-inch piece ginger, peeled", { item: "1 1/2-inch piece ginger", note: "peeled" }],
  ["5-minute sauce", { item: "5-minute sauce" }],
  ["1. Mix the flour", { item: "1. Mix the flour" }],
  ["2 cups", { item: "cups" }],
  ["3 cloves", { item: "cloves" }],
  ["2 eggs or 1/2 cup applesauce", { q: [2], item: "eggs or 1/2 cup applesauce" }],
  ["1 cup milk or cream", { q: [1], u: "cup", item: "milk or cream" }],
  [
    "1 cup sour cream (or plain yogurt)",
    { q: [1], u: "cup", item: "sour cream", note: "or plain yogurt" },
  ],
  [
    "1 cup tomatoes (diced, drained)",
    { q: [1], u: "cup", item: "tomatoes", note: "diced, drained" },
  ],
  ["16 oz. canned pumpkin purée", { q: [16], u: "oz", item: "canned pumpkin purée" }],
  ["6 tbsp. unsalted butter, cubed", { q: [6], u: "tbsp", item: "unsalted butter", note: "cubed" }],
  ["1/0 cup mystery", { item: "1/0 cup mystery" }],
  ["", { item: "" }],
  ["   ", { item: "" }],
];

describe("ingredient corpus", () => {
  it("has at least 120 lines", () => {
    expect(corpus.length).toBeGreaterThanOrEqual(120);
  });

  it.each(corpus.map(([line, e]) => [line, e] as const))("%j", (line, e) => {
    expect(parseIngredientLine(line)).toEqual(full(line, e));
  });
});

describe("parseIngredientLine robustness", () => {
  it("never throws and always echoes the input", () => {
    const weird = [
      "(",
      ")",
      "((",
      "1/",
      "/2",
      "1 -",
      "- -",
      "½",
      "1 (",
      "(optional)",
      ",",
      ", ,",
      "1 to",
      "to 2",
    ];
    for (const line of weird) {
      const parsed = parseIngredientLine(line);
      expect(parsed.original).toBe(line);
      expect(typeof parsed.item).toBe("string");
    }
  });

  it("is deterministic", () => {
    const a = parseIngredientLine("1 1/2 cups (190g) flour, sifted");
    const b = parseIngredientLine("1 1/2 cups (190g) flour, sifted");
    expect(a).toEqual(b);
  });
});

describe("isSectionHeading", () => {
  it.each([
    ["For the sauce:", true],
    ["For the crust", true],
    ["Dressing:", true],
    ["- FOR THE FILLING", true],
    ["2 cups flour", false],
    ["Salt, to taste", false],
    ["Kosher salt", false],
    ["", false],
  ])("%j", (line, expected) => {
    expect(isSectionHeading(line)).toBe(expected);
  });
});
