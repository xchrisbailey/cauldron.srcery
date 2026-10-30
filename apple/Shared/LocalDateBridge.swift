import CauldronKit
import Foundation

enum DayKeyCalendar {
  // Keep local civil-day boundaries without letting the system's display calendar change keys.
  static func make(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  static var current: Calendar { make(timeZone: .current) }
}

extension LocalDate {
  /// The Gregorian civil day `date` falls on in `calendar`'s time zone. Its display calendar is
  /// intentionally ignored because persisted day keys are Gregorian.
  init?(_ date: Date, in calendar: Calendar) {
    let parts = DayKeyCalendar.make(timeZone: calendar.timeZone).dateComponents(
      [.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    self.init(year: year, month: month, day: day)
  }

  /// Midday on this Gregorian civil day in `calendar`'s time zone; the display calendar is
  /// intentionally ignored because persisted day keys are Gregorian.
  func date(in calendar: Calendar) -> Date? {
    DayKeyCalendar.make(timeZone: calendar.timeZone).date(
      from: DateComponents(year: year, month: month, day: day, hour: 12))
  }
}
