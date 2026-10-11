import CauldronKit
import SwiftUI

/// "Stir into the week" on a recipe's page. The week's add flow (#175) fills this in; `scale`
/// carries the servings the cook chose. Until then it shows disabled.
struct RecipeAddToWeekAction: View {
  let recipe: RecipeRecord
  let scale: Scale

  var body: some View {
    Button {
    } label: {
      Text(verbatim: Copy.week.stirIntoWeek.text)
    }
    .buttonStyle(RecipeActionButtonStyle())
    .disabled(true)
  }
}
