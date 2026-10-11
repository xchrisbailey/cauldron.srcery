import CauldronKit
import SwiftUI

/// The gather section's first screen. Until the section is built it shows its empty state;
/// replace the body and keep the name.
struct GatherRoot: View {
  var body: some View {
    NavigationStack {
      EmptyState(
        systemImage: AppDestination.gather.systemImage, message: Copy.gather.empty
      )
      .navigationTitle(AppDestination.gather.title.text)
    }
  }
}

#Preview {
  GatherRoot()
}
