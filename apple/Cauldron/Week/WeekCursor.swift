import CauldronKit
import SwiftData
import SwiftUI

/// Which week a section shows: the one holding today, or the weeks either side of it, counted
/// from the cook's first day of the week. The Week and Gather sections both read it
/// (`week-cursor.ts` in the reference), so the two can't drift.
@MainActor
struct WeekCursor {
  let today: LocalDate
  let startsOn: WeekStartDay
  /// Weeks from the one that holds today.
  let offset: Binding<Int>
  /// Keeps the cook's choice of first day, and returns to this week.
  let setStartsOn: @MainActor (WeekStartDay) -> Void

  /// The first day of the week shown.
  var start: LocalDate {
    today.startOfWeek(startingOn: startsOn).adding(days: offset.wrappedValue * 7)
  }

  var isCurrent: Bool { offset.wrappedValue == 0 }

  func previous() { offset.wrappedValue -= 1 }
  func next() { offset.wrappedValue += 1 }
  func thisWeek() { offset.wrappedValue = 0 }
}

/// Reads the first day of the week from the cook's preference, keeps today fresh, and hands
/// the week to show to `content`.
struct WeekCursorHost<Content: View>: View {
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var scenePhase
  @Query private var preferences: [PreferencesRecord]
  @State private var today = WeekDates.today()
  @State private var offset = 0
  @ViewBuilder let content: (WeekCursor) -> Content

  private var startsOn: WeekStartDay {
    Deduplication.keeper(of: preferences)?.weekStartsOn ?? .monday
  }

  var body: some View {
    content(
      WeekCursor(
        today: today, startsOn: startsOn, offset: $offset, setStartsOn: setStartsOn)
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
