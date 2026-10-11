import CauldronKit
import SwiftUI

/// The offer to divine a recipe's missing numbers from its ingredients, shown where a recipe
/// with gaps is being logged. Estimating needs the AI service (#174), which isn't built yet, so
/// this is disabled and says so. #174 replaces the body: on success it should fill the
/// recipe's numbers (see `RecipeRecord.macros`) and the form reads them again.
struct LogRecipeDivineOffer: View {
  let recipe: RecipeRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
      } label: {
        Text(verbatim: Copy.editor.divineMacros.text).brandText(.control)
      }
      .disabled(true)
      Text(verbatim: Copy.editor.divineUnavailable.text)
        .brandText(.control)
        .foregroundStyle(Brand.Colors.subtext)
    }
  }
}
