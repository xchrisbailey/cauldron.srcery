// A handful of everyday recipes for local development and demos, written for
// Cauldron. Ingredient lines are stored exactly as written and parsed on seed.

export interface SeedRecipe {
  readonly title: string;
  readonly description: string;
  readonly servings: number;
  readonly prepMinutes: number;
  readonly cookMinutes: number;
  readonly tags: ReadonlyArray<{
    readonly name: string;
    readonly kind: "cuisine" | "meal" | "diet" | "other";
  }>;
  /** Lines starting with "## " are section headings. */
  readonly ingredients: ReadonlyArray<string>;
  readonly steps: ReadonlyArray<{ readonly text: string; readonly timerSeconds?: number }>;
  readonly notes?: string;
}

export const seedRecipes: ReadonlyArray<SeedRecipe> = [
  {
    title: "Shakshuka with feta",
    description: "Eggs poached in a spiced tomato and pepper sauce, finished with feta and herbs.",
    servings: 4,
    prepMinutes: 10,
    cookMinutes: 25,
    tags: [
      { name: "Middle Eastern", kind: "cuisine" },
      { name: "Breakfast", kind: "meal" },
      { name: "Vegetarian", kind: "diet" },
    ],
    ingredients: [
      "2 tbsp olive oil",
      "1 onion, diced",
      "1 red bell pepper, sliced",
      "3 cloves garlic, minced",
      "1 tsp ground cumin",
      "1 tsp smoked paprika",
      "1/4 tsp chili flakes (optional)",
      "1 (28-ounce) can crushed tomatoes",
      "Salt and pepper, to taste",
      "6 large eggs",
      "½ cup crumbled feta",
      "2 tbsp chopped parsley, for serving",
    ],
    steps: [
      {
        text: "Warm the olive oil in a large skillet over medium heat. Add the onion and pepper and cook until soft.",
        timerSeconds: 480,
      },
      {
        text: "Stir in the garlic, cumin, paprika and chili flakes and cook for a minute until fragrant.",
        timerSeconds: 60,
      },
      {
        text: "Add the tomatoes, season with salt and pepper, and simmer until slightly thickened.",
        timerSeconds: 600,
      },
      {
        text: "Make six wells in the sauce and crack an egg into each. Cover and cook until the whites are set.",
        timerSeconds: 360,
      },
      { text: "Scatter over the feta and parsley and serve straight from the pan." },
    ],
    notes: "Crusty bread for dipping is not optional in spirit.",
  },
  {
    title: "Weeknight chicken thighs with lemon and garlic",
    description: "Crisp-skinned thighs roasted over potatoes with lemon, garlic and thyme.",
    servings: 4,
    prepMinutes: 15,
    cookMinutes: 40,
    tags: [
      { name: "Dinner", kind: "meal" },
      { name: "Gluten-free", kind: "diet" },
    ],
    ingredients: [
      "2 lbs. chicken thighs, bone-in, skin-on",
      "1 1/2 lb small potatoes, halved",
      "3 tbsp olive oil",
      "1 lemon, sliced",
      "6 cloves garlic, smashed",
      "4 sprigs thyme",
      "1 tsp kosher salt",
      "½ tsp black pepper",
    ],
    steps: [
      { text: "Heat the oven to 220°C (425°F)." },
      { text: "Toss the potatoes with half the oil, salt and pepper in a roasting tin." },
      {
        text: "Rub the chicken with the rest of the oil and season. Nestle it skin side up among the potatoes with the lemon, garlic and thyme.",
      },
      {
        text: "Roast until the skin is crisp and the chicken is cooked through.",
        timerSeconds: 2400,
      },
      {
        text: "Rest for five minutes, then squeeze the roasted lemon over everything.",
        timerSeconds: 300,
      },
    ],
  },
  {
    title: "Overnight oats",
    description: "Oats soaked in milk and yogurt overnight, ready to eat in the morning.",
    servings: 2,
    prepMinutes: 5,
    cookMinutes: 0,
    tags: [
      { name: "Breakfast", kind: "meal" },
      { name: "Vegetarian", kind: "diet" },
    ],
    ingredients: [
      "1 cup rolled oats",
      "1 cup milk",
      "½ cup plain yogurt",
      "1 tbsp chia seeds",
      "1-2 tbsp maple syrup",
      "Pinch of salt",
      "## To serve",
      "1 cup berries",
      "2 tbsp toasted almonds, chopped",
    ],
    steps: [
      { text: "Stir the oats, milk, yogurt, chia, maple syrup and salt together in a jar." },
      { text: "Cover and refrigerate overnight, or at least four hours." },
      { text: "Loosen with a splash of milk and top with berries and almonds." },
    ],
  },
  {
    title: "Tomato and white bean soup",
    description: "A quick pantry soup of canned tomatoes and beans, blended until half smooth.",
    servings: 4,
    prepMinutes: 10,
    cookMinutes: 25,
    tags: [
      { name: "Italian", kind: "cuisine" },
      { name: "Lunch", kind: "meal" },
      { name: "Vegan", kind: "diet" },
    ],
    ingredients: [
      "3 tbsp olive oil",
      "1 onion, finely chopped",
      "2 carrots, diced",
      "4 cloves garlic, sliced",
      "1 tsp dried oregano",
      "1 (14 oz) can diced tomatoes",
      "2 (15 oz) cans cannellini beans, drained and rinsed",
      "4 cups vegetable stock",
      "2 cups spinach",
      "Salt, to taste",
    ],
    steps: [
      {
        text: "Soften the onion and carrots in the olive oil over medium heat.",
        timerSeconds: 600,
      },
      { text: "Add the garlic and oregano and cook for a minute.", timerSeconds: 60 },
      { text: "Add the tomatoes, beans and stock and simmer.", timerSeconds: 900 },
      {
        text: "Blend about half the soup and stir it back in, then wilt in the spinach and season.",
      },
    ],
  },
  {
    title: "Brown butter chocolate chip cookies",
    description: "Chewy cookies with nutty brown butter and a little flaky salt.",
    servings: 24,
    prepMinutes: 20,
    cookMinutes: 12,
    tags: [{ name: "Dessert", kind: "meal" }],
    ingredients: [
      "1 cup (226g) unsalted butter",
      "1 cup packed brown sugar",
      "½ cup granulated sugar",
      "2 large eggs, at room temperature",
      "2 tsp vanilla extract",
      "2 1/4 cups (280g) all-purpose flour",
      "1 tsp baking soda",
      "1 tsp kosher salt",
      "1 1/2 cups chocolate chips",
      "Flaky salt, for sprinkling",
    ],
    steps: [
      {
        text: "Melt the butter in a pan and keep cooking until it smells nutty and the solids turn brown. Let it cool for ten minutes.",
        timerSeconds: 600,
      },
      { text: "Whisk the brown butter with both sugars, then beat in the eggs and vanilla." },
      {
        text: "Fold in the flour, baking soda and salt, then the chocolate chips. Chill the dough.",
        timerSeconds: 1800,
      },
      {
        text: "Heat the oven to 180°C (350°F). Scoop the dough onto lined trays and bake until the edges are golden.",
        timerSeconds: 720,
      },
      { text: "Sprinkle with flaky salt while warm." },
    ],
  },
];
