import CauldronKit
import SwiftUI

/// "Start brewing" on a recipe's page. Brew mode (#169) fills this in: it gets the recipe and
/// the scale the cook chose, to hand on. Until then it shows disabled.
struct RecipeBrewAction: View {
  let recipe: RecipeRecord
  let scale: Scale

  var body: some View {
    Button {
    } label: {
      Text(verbatim: Copy.recipes.startBrewing.text)
    }
    .buttonStyle(RecipeActionButtonStyle(.primary))
    .disabled(true)
  }
}
