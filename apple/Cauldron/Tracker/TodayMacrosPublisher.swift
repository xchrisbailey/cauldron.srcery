import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import WidgetKit

/// Leaves the day's numbers where the macros widget reads them. The widget never opens the store,
/// so after the diary or the targets change the app works the numbers out here, writes the
/// snapshot file in the App Group container, and asks WidgetKit to redraw.
///
/// Every diary write goes through `DiaryEditor`, which publishes; so do saving the targets, a
/// check-in that changes them, and the estimate queue when it fills an entry. The app also
/// publishes when it launches, comes forward or goes to the background, and when midnight
/// passes with it open. A change that arrives by sync from another device is picked up the next
/// time the app comes forward.
@MainActor
final class TodayMacrosPublisher {
  /// The real one. Under test (an in-memory store) it has no folder, so a test run never writes
  /// the real container or pokes the real widget.
  static let shared = TodayMacrosPublisher(
    folder: CauldronStore.launchMode == .inMemory ? nil : TodayMacrosFile.liveFolder(),
    reload: { WidgetCenter.shared.reloadTimelines(ofKind: TodayMacrosWidgetKind.id) })

  private let folder: URL?
  private let now: () -> Date
  private let calendar: Calendar
  private let reload: () -> Void

  /// `folder` is where the file goes; nil writes nothing. `reload` is told after each write.
  init(
    folder: URL?, now: @escaping () -> Date = { .now }, calendar: Calendar = DayKeyCalendar.current,
    reload: @escaping () -> Void = {}
  ) {
    self.folder = folder
    self.now = now
    self.calendar = calendar
    self.reload = reload
  }

  /// Works out today's numbers from `context` and writes them. Returns whether it wrote. A
  /// store that can't be read, or a folder that can't be written, leaves the last snapshot as
  /// it was: the widget would rather be a little behind than wrong.
  @discardableResult
  func publish(from context: ModelContext) -> Bool {
    guard folder != nil else { return false }
    do {
      let snapshot = try snapshot(from: context)
      try TodayMacrosFile.write(snapshot, to: folder)
      reload()
      return true
    } catch {
      return false
    }
  }

  /// Today's snapshot: the day's entries, with the totals the diary's header shows, against
  /// the saved targets.
  func snapshot(from context: ModelContext) throws -> TodayMacrosSnapshot {
    let date = now()
    guard let today = LocalDate(date, in: calendar) else { throw CocoaError(.fileReadUnknown) }
    let key = today.description
    let records = try context.fetch(
      FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.dayKey == key }))
    return TodayMacrosSnapshot.make(
      day: today, entries: DayLog(day: today, records: records).sections.flatMap(\.entries),
      hasWaitingEntry: records.contains(where: \.macrosPending),
      targets: try context.current(TargetsRecord.self)?.macroTargets, now: date)
  }
}

private struct PublishesTodayMacros: ViewModifier {
  let context: ModelContext
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
      // On launch, and each time the scene comes forward, goes inactive or goes to the
      // background. This is also how a change that arrived by sync reaches the widget.
      .task(id: scenePhase) { TodayMacrosPublisher.shared.publish(from: context) }
      // A day that ends with the app open: the widget starts the new day with nothing eaten.
      .task {
        while !Task.isCancelled {
          let wait = DayRollover.secondsUntilMidnight(now: .now, calendar: .current)
          try? await Task.sleep(for: .seconds(wait + 1))
          if Task.isCancelled { return }
          TodayMacrosPublisher.shared.publish(from: context)
        }
      }
  }
}

extension View {
  /// Keeps the macros widget's snapshot fresh while the app runs. See `TodayMacrosPublisher`.
  func publishesTodayMacros(from context: ModelContext) -> some View {
    modifier(PublishesTodayMacros(context: context))
  }
}
