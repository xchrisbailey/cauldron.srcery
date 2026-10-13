import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

#if DEBUG
  /// The seeded week's Gather list as the TypeScript reference builds it. Produced by running
  /// `readIngredientBlock`, `gatherWeek`, `reconcile`, `sortRows` and `measureParts` from
  /// `@cauldron/shared` (and the row codec's four-decimal rounding from `@cauldron/db`) over
  /// `packages/db/src/seed-recipes.ts` with the five entries `DebugSeed` plans, in Bun. Each row
  /// is its aisle, item, amount, unit label and the recipes it is for.
  enum SeededGatherReference {
    enum Recipe: String {
      case oats = "Overnight oats"
      case soup = "Tomato and white bean soup"
      case shakshuka = "Shakshuka with feta"
      case chicken = "Weeknight chicken thighs with lemon and garlic"
      case cookies = "Brown butter chocolate chip cookies"
    }

    struct ExpectedRow: Equatable {
      let aisle: Aisle
      let item: String
      let amount: String?
      let unit: String?
      let recipes: [Recipe]

      init(_ aisle: Aisle, _ item: String, _ amount: String?, _ unit: String?, _ recipes: [Recipe])
      {
        self.aisle = aisle
        self.item = item
        self.amount = amount
        self.unit = unit
        self.recipes = recipes
      }
    }

    static let recipeCount = 5

    static let rows: [ExpectedRow] = [
      ExpectedRow(.produce, "berries", "1", "c", [.oats]),
      ExpectedRow(.produce, "carrots", "2", nil, [.soup]),
      ExpectedRow(.produce, "chopped parsley", "2", "tbsp", [.shakshuka]),
      ExpectedRow(.produce, "garlic", "13", "cloves", [.shakshuka, .soup, .chicken]),
      ExpectedRow(.produce, "lemon", "1", nil, [.chicken]),
      ExpectedRow(.produce, "onion", "2", nil, [.shakshuka, .soup]),
      ExpectedRow(.produce, "red bell pepper", "1", nil, [.shakshuka]),
      ExpectedRow(.produce, "small potatoes", "1 ½", "lb", [.chicken]),
      ExpectedRow(.produce, "spinach", "2", "c", [.soup]),
      ExpectedRow(.produce, "thyme", "4", "sprigs", [.chicken]),
      ExpectedRow(.meat, "chicken thighs", "2", "lb", [.chicken]),
      ExpectedRow(.dairy, "crumbled feta", "½", "c", [.shakshuka]),
      ExpectedRow(.dairy, "large eggs", "7", nil, [.cookies, .shakshuka]),
      ExpectedRow(.dairy, "milk", "1", "c", [.oats]),
      ExpectedRow(.dairy, "plain yogurt", "½", "c", [.oats]),
      ExpectedRow(.dairy, "unsalted butter", "½", "c", [.cookies]),
      ExpectedRow(.pantry, "all-purpose flour", "1 ⅛", "c", [.cookies]),
      ExpectedRow(.pantry, "baking soda", "½", "tsp", [.cookies]),
      ExpectedRow(.pantry, "cannellini beans", "2", "cans", [.soup]),
      ExpectedRow(.pantry, "chia seeds", "1", "tbsp", [.oats]),
      ExpectedRow(.pantry, "chocolate chips", "¾", "c", [.cookies]),
      ExpectedRow(.pantry, "crushed tomatoes", "1", "can", [.shakshuka]),
      ExpectedRow(.pantry, "diced tomatoes", "1", "can", [.soup]),
      ExpectedRow(.pantry, "granulated sugar", "¼", "c", [.cookies]),
      ExpectedRow(.pantry, "maple syrup", "1–2", "tbsp", [.oats]),
      ExpectedRow(.pantry, "olive oil", "8", "tbsp", [.shakshuka, .soup, .chicken]),
      ExpectedRow(.pantry, "packed brown sugar", "½", "c", [.cookies]),
      ExpectedRow(.pantry, "rolled oats", "1", "c", [.oats]),
      ExpectedRow(.pantry, "toasted almonds", "2", "tbsp", [.oats]),
      ExpectedRow(.pantry, "vanilla extract", "1", "tsp", [.cookies]),
      ExpectedRow(.pantry, "vegetable stock", "4", "c", [.soup]),
      ExpectedRow(.spices, "black pepper", "½", "tsp", [.chicken]),
      ExpectedRow(.spices, "chili flakes", "¼", "tsp", [.shakshuka]),
      ExpectedRow(.spices, "dried oregano", "1", "tsp", [.soup]),
      ExpectedRow(.spices, "Flaky salt", nil, nil, [.cookies]),
      ExpectedRow(.spices, "ground cumin", "1", "tsp", [.shakshuka]),
      ExpectedRow(.spices, "kosher salt", "1 ½", "tsp", [.cookies, .chicken]),
      ExpectedRow(.spices, "Pinch of salt", nil, nil, [.oats]),
      ExpectedRow(.spices, "Salt", nil, nil, [.soup]),
      ExpectedRow(.spices, "Salt and pepper", nil, nil, [.shakshuka]),
      ExpectedRow(.spices, "smoked paprika", "1", "tsp", [.shakshuka]),
    ]
  }
#endif
