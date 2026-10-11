import CauldronKit
import SwiftData
import SwiftUI

/// The tracker section's first screen. Until targets are set it is the set-up; after that it
/// is the diary's place (an empty state for now), with the targets a tap away to change.
struct TrackerRoot: View {
  @Query private var targets: [TargetsRecord]
  @State private var changingTargets = false

  var body: some View {
    NavigationStack {
      if targets.isEmpty {
        TargetsView()
      } else {
        EmptyState(
          systemImage: AppDestination.tracker.systemImage, message: Copy.tracker.diary.empty
        )
        .navigationTitle(AppDestination.tracker.title.text)
        .toolbar {
          ToolbarItem {
            Button(Copy.tracker.targets.pageTitle.text) { changingTargets = true }
          }
        }
      }
    }
    .sheet(isPresented: $changingTargets) {
      NavigationStack {
        TargetsView(onSaved: { changingTargets = false })
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button(Copy.ui.close.text) { changingTargets = false }
            }
          }
      }
      #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
      #endif
    }
  }
}

#Preview {
  if let container = try? CauldronStore.container(.inMemory) {
    TrackerRoot()
      .modelContainer(container)
  }
}
