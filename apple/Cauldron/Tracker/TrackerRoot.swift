import CauldronKit
import SwiftData
import SwiftUI

/// The tracker section's first screen. Until targets are set it is the set-up; after that it
/// is the diary, with the targets a tap away to change.
struct TrackerRoot: View {
  @Environment(\.modelContext) private var context
  @Query private var targets: [TargetsRecord]
  @State private var changingTargets = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      if Deduplication.keeper(of: targets) == nil {
        TargetsView(context: context)
      } else {
        diary
          .navigationTitle(AppDestination.tracker.title.text)
          .toolbar {
            ToolbarItemGroup {
              if let today = TargetsForm.today() {
                NavigationLink(Copy.tracker.weight.link.text) { WeightView(today: today) }
              }
              Button(Copy.tracker.targets.pageTitle.text) { changingTargets = true }
            }
          }
      }
    }
    .task { await checkHealth() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await checkHealth() } }
    }
    .sheet(isPresented: $changingTargets) {
      NavigationStack {
        TargetsView(context: context, onSaved: { changingTargets = false })
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

  /// Weights from Health come in when the tracker opens and whenever the app comes forward.
  private func checkHealth() async {
    guard let today = TargetsForm.today() else { return }
    await HealthSync.shared.importWeights(into: context, today: today)
  }

  @ViewBuilder
  private var diary: some View {
    if let today = TargetsForm.today() {
      DiaryView(
        today: today, targets: Deduplication.keeper(of: targets),
        openTargets: { changingTargets = true })
    } else {
      EmptyState(
        systemImage: AppDestination.tracker.systemImage, message: Copy.tracker.diary.couldntLoad)
    }
  }
}

#Preview {
  if let container = try? CauldronStore.container(.inMemory) {
    TrackerRoot()
      .modelContainer(container)
  }
}
