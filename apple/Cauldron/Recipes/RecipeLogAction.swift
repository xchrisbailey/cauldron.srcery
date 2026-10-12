import CauldronKit
import SwiftUI

/// "Log it" on a recipe's page: opens the log sheet (servings, meal, day) for this recipe.
struct RecipeLogAction: View {
  let recipe: RecipeRecord

  @State private var logging = false

  var body: some View {
    Button {
      logging = true
    } label: {
      Text(verbatim: Copy.tracker.logRecipe.title.text)
    }
    .buttonStyle(RecipeActionButtonStyle())
    .sheet(isPresented: $logging) {
      RecipeLogSheet(recipe: recipe, onClose: { logging = false })
    }
  }
}
