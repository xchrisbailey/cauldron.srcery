import CauldronKit
import SwiftData
import SwiftUI

/// The week section: a calendar of the week's meals with the calories and macros they add up
/// to, and the weeks either side. It reads the week's first day from the cook's preference and
/// hands one week at a time to `WeekPlanner`.
struct WeekRoot: View {
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var scenePhase
  @Query private var preferences: [PreferencesRecord]
  @State private var today = WeekDates.today()
  /// Weeks from the one that holds today.
  @State private var offset = 0

  private var startsOn: WeekStartDay {
    Deduplication.keeper(of: preferences)?.weekStartsOn ?? .monday
  }

  private var start: LocalDate {
    today.startOfWeek(startingOn: startsOn).adding(days: offset * 7)
  }

  var body: some View {
    WeekPlanner(
      start: start, today: today, startsOn: startsOn, isCurrent: offset == 0,
      onPrevious: { offset -= 1 }, onNext: { offset += 1 }, onThisWeek: { offset = 0 },
      onStartsOn: setStartsOn
    )
    .onChange(of: scenePhase) {
      if scenePhase == .active { today = WeekDates.today() }
    }
  }

  private func setStartsOn(_ day: WeekStartDay) {
    let record = Deduplication.keeper(of: preferences) ?? PreferencesRecord()
    if record.modelContext == nil { context.insert(record) }
    record.weekStartsOn = day
    offset = 0
    try? context.save()
  }
}

#if DEBUG
  #Preview("Week") {
    let container = RecipePreviewData.container()
    WeekRoot()
      .modelContainer(container)
  }
#endif
