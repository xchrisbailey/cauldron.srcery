#if os(macOS)
  import CauldronKit
  import SwiftData
  import SwiftUI

  /// The Mac's brew window: the recipe cooked through in a window of its own, with the arrow
  /// keys for Previous and Next and Space for the step's timer. No Live Activity; the finished
  /// timers' notifications still apply.
  struct BrewWindow: View {
    let request: BrewRequest
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var session: BrewSession?

    var body: some View {
      Group {
        if let session {
          BrewScreen(model: session.model, recipe: session.recipe, onClose: { dismiss() })
            .navigationTitle(session.recipe.title)
        } else {
          EmptyState(systemImage: "timer", message: Copy.recipeView.notFound)
        }
      }
      .frame(minWidth: 480, minHeight: 560)
      .task {
        guard session == nil else { return }
        session = BrewSession.make(
          recipeID: request.recipeID, scale: request.scale, context: context)
      }
    }
  }
#endif
