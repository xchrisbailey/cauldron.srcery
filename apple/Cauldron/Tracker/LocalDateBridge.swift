import CauldronKit
import Foundation

extension LocalDate {
  /// The calendar day `date` falls on in `calendar`.
  init?(_ date: Date, in calendar: Calendar) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    self.init(year: year, month: month, day: day)
  }

  /// Midday on this day in `calendar`, which no time zone moves to another day.
  func date(in calendar: Calendar) -> Date? {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
  }
}
