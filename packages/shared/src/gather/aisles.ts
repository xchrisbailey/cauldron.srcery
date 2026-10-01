import { Schema } from "effect";

/**
 * Store aisles for the Gather list (#19), and a small item-to-aisle map.
 *
 * The map is a list of rules over the normalized item key (see
 * `ingredientKey`), checked in order, so specific phrases ("olive oil",
 * "chicken stock", "crushed tomato") come before the single words they
 * contain ("olive", "chicken", "tomato"). Anything unmatched is "other".
 */

export const AISLES = [
  "produce",
  "meat",
  "dairy",
  "bakery",
  "pantry",
  "spices",
  "frozen",
  "drinks",
  "other",
] as const;
export const Aisle = Schema.Literals(AISLES);
export type Aisle = typeof Aisle.Type;

const words = (list: string) => list.trim().split(/\s*,\s*/);

/** [phrases, aisle]: a rule matches when the key contains a phrase as whole words. */
const RULES: ReadonlyArray<readonly [ReadonlyArray<string>, Aisle]> = [
  // Phrases that would otherwise fall into the wrong aisle.
  [words("frozen pea, frozen corn, frozen spinach, frozen berry, ice cream, frozen"), "frozen"],
  [words("orange juice, apple juice, lemonade"), "drinks"],
  [
    words(`garlic powder, onion powder, ground pepper, cream of tartar, garlic salt, onion salt,
      celery salt, celery seed, mustard seed, fennel seed`),
    "spices",
  ],
  [
    words(`olive oil, vegetable oil, canola oil, sesame oil, coconut oil, coconut milk,
      cider vinegar, wine vinegar, balsamic vinegar, rice vinegar, coconut cream, egg noodle,
      chicken stock, beef stock, vegetable stock, chicken broth, beef broth, vegetable broth, stock, broth,
      crushed tomato, diced tomato, chopped tomato, tomato paste, tomato puree, tomato sauce,
      can tomato, tin tomato, canned tomato, sun-dried tomato, cannellini bean, black bean,
      kidney bean, chickpea, lentil, peanut butter, maple syrup, soy sauce, fish sauce,
      chocolate chip, baking soda, baking powder, vanilla extract, brown sugar, granulated sugar,
      powdered sugar, icing sugar, cocoa, rolled oats, oats, breadcrumb, panko`),
    "pantry",
  ],
  [
    words(`chili flake, red pepper flake, black pepper, white pepper, peppercorn, kosher salt,
      sea salt, flaky salt, salt and pepper, salt, ground cumin, cumin, smoked paprika, paprika,
      turmeric, coriander seed, ground coriander, cinnamon, nutmeg, ground clove, whole clove, cardamom,
      dried oregano, dried thyme, dried basil, bay leaf, chili powder, curry powder, garam masala,
      cayenne, allspice, ginger powder, ground ginger`),
    "spices",
  ],
  [
    words(`unsalted butter, salted butter, butter, milk, buttermilk, cream, sour cream, yogurt,
      greek yogurt, egg, cheese, feta, parmesan, cheddar, mozzarella, ricotta, halloumi,
      cream cheese, mascarpone`),
    "dairy",
  ],
  [
    words(`chicken, chicken thigh, chicken breast, beef, ground beef, pork, bacon, sausage, lamb,
      turkey, ham, chorizo, prosciutto, salmon, cod, tuna, shrimp, prawn, fish, anchovy, mussel`),
    "meat",
  ],
  [
    words("bread, baguette, tortilla, pita, bun, roll, naan, sourdough, croissant, bagel"),
    "bakery",
  ],
  [
    words(`onion, red onion, shallot, garlic, ginger, scallion, spring onion, leek, carrot, celery,
      potato, sweet potato, tomato, cherry tomato, bell pepper, red bell pepper, pepper, chili,
      jalapeno, zucchini, courgette, eggplant, aubergine, cucumber, lettuce, spinach, kale,
      arugula, rocket, cabbage, broccoli, cauliflower, mushroom, avocado, lemon, lime, orange,
      apple, banana, berry, blueberry, strawberry, raspberry, grape, pear, peach, mango,
      parsley, cilantro, coriander, basil, mint, dill, thyme, rosemary, sage, chive, oregano,
      herb, squash, pumpkin, corn, pea, green bean, asparagus, beet, radish, fennel`),
    "produce",
  ],
  [
    words(`flour, all-purpose flour, sugar, rice, pasta, spaghetti, noodle, quinoa, couscous,
      bean, honey, vinegar, mustard, ketchup, mayonnaise, oil, almond, walnut, pecan, cashew,
      peanut, pine nut, seed, chia seed, sesame seed, raisin, yeast, cornstarch, gelatin,
      chocolate, jam, tahini, miso, curry paste, coconut`),
    "pantry",
  ],
  [words("water, wine, beer, juice, coffee, tea, soda, sparkling water"), "drinks"],
];

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const COMPILED = RULES.map(
  ([phrases, aisle]) =>
    [new RegExp(`(?:^|\\s)(?:${phrases.map(escape).join("|")})(?:s|es)?(?=$|\\s)`), aisle] as const,
);

/** The aisle an item is usually found in, from its normalized key. */
export function aisleFor(itemKey: string): Aisle {
  for (const [pattern, aisle] of COMPILED) if (pattern.test(itemKey)) return aisle;
  return "other";
}
