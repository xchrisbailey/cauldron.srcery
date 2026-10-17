import CauldronKit
import SwiftUI

/// The offer to divine a recipe's missing numbers from its ingredients, shown where a recipe
/// with gaps is being logged. It is the same control as on the recipe's page; when the
/// estimate arrives the recipe's numbers fill in and the form reads them again.
struct LogRecipeDivineOffer: View {
  let recipe: RecipeRecord

  var body: some View {
    RecipeDivineControl(recipe: recipe)
  }
}
