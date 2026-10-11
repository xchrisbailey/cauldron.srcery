#if DEBUG
  import CauldronKit

  // A handful of everyday recipes for development and demos, ported from
  // `packages/db/src/seed-recipes.ts`. Ingredient lines are stored as written and parsed when
  // the seed runs.

  struct SeedRecipe {
    var title: String
    var description: String
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    /// Per serving; left out to show a recipe without them.
    var macros: Macros?
    var tags: [(name: String, kind: TagKind)]
    /// Headings ("## To serve") start a section, as `readHeading` reads them.
    var ingredients: [String]
    var steps: [(text: String, timerSeconds: Int?)]
    var notes: String?
  }

  extension DebugSeed {
    static let recipes: [SeedRecipe] = [
      SeedRecipe(
        title: "Shakshuka with feta",
        description:
          "Eggs poached in a spiced tomato and pepper sauce, finished with feta and herbs.",
        servings: 4, prepMinutes: 10, cookMinutes: 25,
        macros: Macros(calories: 310, protein: 17, carbs: 18, fat: 19),
        tags: [("Middle Eastern", .cuisine), ("Breakfast", .meal), ("Vegetarian", .diet)],
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
          (
            "Warm the olive oil in a large skillet over medium heat. Add the onion and pepper and cook until soft.",
            480
          ),
          (
            "Stir in the garlic, cumin, paprika and chili flakes and cook for a minute until fragrant.",
            60
          ),
          (
            "Add the tomatoes, season with salt and pepper, and simmer until slightly thickened.",
            600
          ),
          (
            "Make six wells in the sauce and crack an egg into each. Cover and cook until the whites are set.",
            360
          ),
          ("Scatter over the feta and parsley and serve straight from the pan.", nil),
        ],
        notes: "Crusty bread for dipping is not optional in spirit."),
      SeedRecipe(
        title: "Weeknight chicken thighs with lemon and garlic",
        description: "Crisp-skinned thighs roasted over potatoes with lemon, garlic and thyme.",
        servings: 4, prepMinutes: 15, cookMinutes: 40,
        macros: Macros(calories: 420, protein: 34, carbs: 6, fat: 28),
        tags: [("Dinner", .meal), ("Gluten-free", .diet)],
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
          ("Heat the oven to 220°C (425°F).", nil),
          ("Toss the potatoes with half the oil, salt and pepper in a roasting tin.", nil),
          (
            "Rub the chicken with the rest of the oil and season. Nestle it skin side up among the potatoes with the lemon, garlic and thyme.",
            nil
          ),
          ("Roast until the skin is crisp and the chicken is cooked through.", 2400),
          ("Rest for five minutes, then squeeze the roasted lemon over everything.", 300),
        ],
        notes: nil),
      SeedRecipe(
        title: "Overnight oats",
        description: "Oats soaked in milk and yogurt overnight, ready to eat in the morning.",
        servings: 2, prepMinutes: 5, cookMinutes: 0,
        macros: Macros(calories: 380, protein: 14, carbs: 58, fat: 10),
        tags: [("Breakfast", .meal), ("Vegetarian", .diet)],
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
          ("Stir the oats, milk, yogurt, chia, maple syrup and salt together in a jar.", nil),
          ("Cover and refrigerate overnight, or at least four hours.", nil),
          ("Loosen with a splash of milk and top with berries and almonds.", nil),
        ],
        notes: nil),
      SeedRecipe(
        title: "Tomato and white bean soup",
        description: "A quick pantry soup of canned tomatoes and beans, blended until half smooth.",
        servings: 4, prepMinutes: 10, cookMinutes: 25,
        macros: Macros(calories: 260, protein: 12, carbs: 38, fat: 7),
        tags: [("Italian", .cuisine), ("Lunch", .meal), ("Vegan", .diet)],
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
          ("Soften the onion and carrots in the olive oil over medium heat.", 600),
          ("Add the garlic and oregano and cook for a minute.", 60),
          ("Add the tomatoes, beans and stock and simmer.", 900),
          (
            "Blend about half the soup and stir it back in, then wilt in the spinach and season.",
            nil
          ),
        ],
        notes: nil),
      SeedRecipe(
        title: "Brown butter chocolate chip cookies",
        description: "Chewy cookies with nutty brown butter and a little flaky salt.",
        servings: 24, prepMinutes: 20, cookMinutes: 12,
        macros: nil,
        tags: [("Dessert", .meal)],
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
          (
            "Melt the butter in a pan and keep cooking until it smells nutty and the solids turn brown. Let it cool for ten minutes.",
            600
          ),
          ("Whisk the brown butter with both sugars, then beat in the eggs and vanilla.", nil),
          (
            "Fold in the flour, baking soda and salt, then the chocolate chips. Chill the dough.",
            1800
          ),
          (
            "Heat the oven to 180°C (350°F). Scoop the dough onto lined trays and bake until the edges are golden.",
            720
          ),
          ("Sprinkle with flaky salt while warm.", nil),
        ],
        notes: nil),
    ]
  }
#endif
