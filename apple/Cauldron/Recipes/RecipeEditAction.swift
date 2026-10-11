import CauldronKit
import SwiftUI

/// "Edit" on a recipe's page. The editor (#168) fills this in, with whatever presents it.
/// Until then it shows disabled.
struct RecipeEditAction: View {
  let recipe: RecipeRecord

  var body: some View {
    Button {
    } label: {
      Text(verbatim: Copy.recipeView.edit.text)
    }
    .buttonStyle(RecipeActionButtonStyle())
    .disabled(true)
  }
}
