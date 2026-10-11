import CauldronKit
import SwiftUI

/// The week section's first screen. Until the section is built it shows its empty state;
/// replace the body and keep the name.
struct WeekRoot: View {
  var body: some View {
    NavigationStack {
      EmptyState(
        systemImage: AppDestination.week.systemImage, message: Copy.week.empty
      )
      .navigationTitle(AppDestination.week.title.text)
    }
  }
}

#Preview {
  WeekRoot()
}
