import CauldronKit
import SwiftUI

/// The tracker section's first screen. Until the section is built it shows its empty state;
/// replace the body and keep the name.
struct TrackerRoot: View {
  var body: some View {
    NavigationStack {
      EmptyState(
        systemImage: AppDestination.tracker.systemImage, message: Copy.tracker.diary.empty
      )
      .navigationTitle(AppDestination.tracker.title.text)
    }
  }
}

#Preview {
  TrackerRoot()
}
