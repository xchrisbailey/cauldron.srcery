import CauldronKit
import Foundation

enum DayKeyCalendar {
  static func make(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  static var current: Calendar { make(timeZone: .current) }
}

extension LocalDate {
  /// The calendar day `date` falls on in `calendar`.
  init?(_ date: Date, in calendar: Calendar) {
    let parts = DayKeyCalendar.make(timeZone: calendar.timeZone).dateComponents(
      [.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    self.init(year: year, month: month, day: day)
  }

  /// Midday on this day in `calendar`, which no time zone moves to another day.
  func date(in calendar: Calendar) -> Date? {
    DayKeyCalendar.make(timeZone: calendar.timeZone).date(
      from: DateComponents(year: year, month: month, day: day, hour: 12))
  }
}
