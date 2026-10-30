import CauldronKit
import Foundation

/// Labels for calendar days, in the viewer's locale. A `LocalDate` is a day on the cook's own
/// calendar, so each label is built at noon on that day and can't slip across midnight.
enum WeekDates {
  /// Today in the cook's own calendar.
  static func today(now: Date = .now, calendar: Calendar = DayKeyCalendar.current) -> LocalDate {
    let parts = DayKeyCalendar.make(timeZone: calendar.timeZone).dateComponents(
      [.year, .month, .day], from: now)
    guard let year = parts.year, let month = parts.month, let day = parts.day,
      let today = LocalDate(year: year, month: month, day: day)
    else { preconditionFailure("The calendar has no day for now.") }
    return today
  }

  /// "Wednesday" or "Wed".
  static func weekday(_ day: LocalDate, long: Bool, locale: Locale = .current) -> String {
    format(day, locale: locale) { style in
      style.weekday(long ? .wide : .abbreviated)
    }
  }

  /// The day of the month: "1".
  static func dayOfMonth(_ day: LocalDate) -> String { String(day.day) }

  /// "Wednesday, Oct 1" or "Wed, Oct 1".
  static func label(_ day: LocalDate, long: Bool, locale: Locale = .current) -> String {
    format(day, locale: locale) { style in
      style.weekday(long ? .wide : .abbreviated).month(.abbreviated).day()
    }
  }

  /// "Oct 1".
  static func monthDay(_ day: LocalDate, locale: Locale = .current) -> String {
    format(day, locale: locale) { $0.month(.abbreviated).day() }
  }

  /// "Sep 28 – Oct 4" for the week starting on `start`.
  static func rangeLabel(start: LocalDate, locale: Locale = .current) -> String {
    "\(monthDay(start, locale: locale)) – \(monthDay(start.adding(days: 6), locale: locale))"
  }

  private static func format(
    _ day: LocalDate, locale: Locale,
    _ build: (Date.FormatStyle) -> Date.FormatStyle
  ) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
    guard let date = calendar.date(from: parts) else { return day.description }
    let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).locale(locale)
    return date.formatted(build(style))
  }
}
