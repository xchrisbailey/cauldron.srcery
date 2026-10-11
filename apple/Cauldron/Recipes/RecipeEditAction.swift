import CauldronKit
import SwiftUI

/// "Edit" on a recipe's page: opens the editor on this recipe.
struct RecipeEditAction: View {
  let recipe: RecipeRecord
  @State private var editing = false

  var body: some View {
    Button {
      editing = true
    } label: {
      Text(verbatim: Copy.recipeView.edit.text)
    }
    .buttonStyle(RecipeActionButtonStyle())
    .sheet(isPresented: $editing) {
      RecipeEditorSheet(recipe: recipe)
    }
  }
}
