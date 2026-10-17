import CauldronKit
import SwiftUI

/// "Edit" on a recipe's page: opens the editor on this recipe.
struct RecipeEditAction: View {
  let recipe: RecipeRecord
  /// Where the page keeps whether the editor is open, so the Recipe menu can open it too.
  var isEditing: Binding<Bool>?
  @State private var ownEditing = false

  private var editing: Binding<Bool> { isEditing ?? $ownEditing }

  var body: some View {
    Button {
      editing.wrappedValue = true
    } label: {
      Text(verbatim: Copy.recipeView.edit.text)
    }
    .buttonStyle(RecipeActionButtonStyle())
    .sheet(isPresented: editing) {
      RecipeEditorSheet(recipe: recipe)
    }
  }
}
