import CauldronKit
import SwiftUI
import WidgetKit

/// The day's macros: eaten against target, for the Home Screen, the Lock Screen and the Mac
/// desktop. It reads the snapshot the app leaves in the App Group container and never opens the
/// store. The views are in `Shared/TodayMacros`, so the app's tests can draw them.
struct TodayMacrosWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: TodayMacrosWidgetKind.id, provider: TodayMacrosProvider()) { entry in
      TodayMacrosWidgetView(entry: entry)
    }
    .configurationDisplayName(Copy.tracker.widget.displayName.text)
    .description(Copy.tracker.widget.description.text)
    .supportedFamilies(Self.families)
  }

  private static var families: [WidgetFamily] {
    #if os(iOS)
      [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular]
    #else
      [.systemSmall, .systemMedium]
    #endif
  }
}

struct TodayMacrosProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayMacrosEntry {
    TodayMacrosEntry(date: .now, snapshot: Self.sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (TodayMacrosEntry) -> Void) {
    // The gallery shows made-up numbers; a widget already placed shows the real ones.
    completion(
      context.isPreview
        ? TodayMacrosEntry(date: .now, snapshot: Self.sample)
        : Self.plan(now: .now).entries[0])
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayMacrosEntry>) -> Void)
  {
    let plan = Self.plan(now: .now)
    completion(Timeline(entries: plan.entries, policy: .after(plan.refreshAt)))
  }

  private static func plan(now: Date) -> TodayMacrosTimeline.Plan {
    TodayMacrosTimeline.plan(
      snapshot: TodayMacrosFile.read(from: TodayMacrosFile.liveFolder()), now: now,
      calendar: DayKeyCalendar.current)
  }

  /// Made-up numbers for the placeholder and the gallery.
  private static var sample: TodayMacrosSnapshot? {
    LocalDate(.now, in: DayKeyCalendar.current).map { day in
      TodayMacrosSnapshot(
        day: day, eaten: MacroTotals(calories: 1240, protein: 82, carbs: 130, fat: 41),
        targets: MacroTargets(calories: 2000, protein: 140, carbs: 220, fat: 65),
        hasWaitingEntry: false, writtenAt: .now)
    }
  }
}
