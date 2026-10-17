import CauldronKit
import SwiftData
import SwiftUI

/// "Start brewing" on a recipe's page: opens brew mode at the scale the cook chose. On iPhone
/// and iPad it covers the screen; on the Mac it opens a window of its own.
struct RecipeBrewAction: View {
  let recipe: RecipeRecord
  let scale: Scale

  @Environment(\.modelContext) private var context
  #if os(iOS)
    @State private var session: BrewSession?
  #else
    @Environment(\.openWindow) private var openWindow
  #endif

  var body: some View {
    Button(action: start) {
      Text(verbatim: Copy.recipes.startBrewing.text)
    }
    .buttonStyle(RecipeActionButtonStyle(.primary))
    #if os(iOS)
      .fullScreenCover(item: $session) { session in
        BrewScreen(model: session.model, recipe: session.recipe, onClose: { self.session = nil })
      }
    #endif
  }

  private func start() {
    #if os(iOS)
      session = BrewSession.make(recipe: recipe, scale: scale, context: context)
    #else
      openWindow(value: BrewRequest(recipeID: recipe.id, scale: scale))
    #endif
  }
}
