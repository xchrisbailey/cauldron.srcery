import CauldronKit
import SwiftData
import SwiftUI

/// The tracker section's first screen. Until targets are set it is the set-up; after that it
/// is the diary's place (an empty state for now), with the targets a tap away to change.
struct TrackerRoot: View {
  @Environment(\.modelContext) private var context
  /// Nil until the store has been read.
  @State private var hasTargets: Bool?
  @State private var changingTargets = false

  var body: some View {
    NavigationStack {
      switch hasTargets {
      case nil:
        Brand.Colors.base.ignoresSafeArea()
      case false?:
        TargetsView(onSaved: refresh)
      case true?:
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
    .task {
      refresh()
      // Targets can arrive from another device too, and a save anywhere is a change.
      for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
        refresh()
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

  private func refresh() {
    hasTargets = (try? context.current(TargetsRecord.self)) != nil
  }
}

#Preview {
  if let container = try? CauldronStore.container(.inMemory) {
    TrackerRoot()
      .modelContainer(container)
  }
}
