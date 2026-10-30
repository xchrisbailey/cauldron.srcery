import CauldronKit
import Foundation
import WidgetKit

/// The widget's kind, which the app names when it asks WidgetKit to reload the timeline.
enum TodayMacrosWidgetKind {
  static let id = "computer.srcery.cauldron.todayMacros"
}

/// What the widget draws at one moment.
struct TodayMacrosEntry: TimelineEntry, Equatable {
  let date: Date
  /// The numbers as seen on `date`, or nil when the app has never left any.
  let snapshot: TodayMacrosSnapshot?
}

/// The timeline the widget hands WidgetKit: now, then the same targets with nothing eaten from
/// the next midnight, and a refresh just after it. Works in the widget's own calendar, so a
/// snapshot written on another day never shows as today's food.
enum TodayMacrosTimeline {
  struct Plan: Equatable {
    var entries: [TodayMacrosEntry]
    var refreshAt: Date
  }

  static func plan(snapshot: TodayMacrosSnapshot?, now: Date, calendar: Calendar) -> Plan {
    let midnight =
      calendar.nextDate(
        after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
        matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
    func entry(at date: Date) -> TodayMacrosEntry {
      guard let snapshot, !snapshot.day.isLegacyCalendarKey,
        let today = LocalDate(date, in: calendar)
      else {
        return TodayMacrosEntry(date: date, snapshot: nil)
      }
      return TodayMacrosEntry(date: date, snapshot: snapshot.seen(on: today))
    }
    return Plan(
      entries: [entry(at: now), entry(at: midnight)], refreshAt: midnight.addingTimeInterval(1))
  }
}
