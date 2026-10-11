import CauldronKit
import SwiftUI

/// The recipes section's first screen. Until the section is built it shows its empty state;
/// replace the body and keep the name.
struct RecipesRoot: View {
  var body: some View {
    NavigationStack {
      EmptyState(
        systemImage: AppDestination.recipes.systemImage, message: Copy.recipes.empty
      )
      .navigationTitle(AppDestination.recipes.title.text)
    }
  }
}

#Preview {
  RecipesRoot()
}
