/// Day of the week, 0 for Sunday to 6 for Saturday.
public enum Weekday: Int, Sendable, Hashable, Codable, CaseIterable {
  case sunday = 0
  case monday
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday
}

/// Which day a week starts on: any day, Monday by default. The raw values are `Weekday`'s, so
/// a stored one means the same day in both.
public enum WeekStartDay: Int, Sendable, Hashable, Codable, CaseIterable {
  case sunday = 0
  case monday = 1
  case tuesday = 2
  case wednesday = 3
  case thursday = 4
  case friday = 5
  case saturday = 6

  /// The week start a cook who has not chosen one gets.
  public static let standard = WeekStartDay.monday

  /// The same day as a `Weekday`.
  public var weekday: Weekday {
    switch self {
    case .sunday: .sunday
    case .monday: .monday
    case .tuesday: .tuesday
    case .wednesday: .wednesday
    case .thursday: .thursday
    case .friday: .friday
    case .saturday: .saturday
    }
  }
}

/// A calendar day, `YYYY-MM-DD`, in the cook's own calendar.
///
/// It is never a `Date` at local midnight, so a day is the same day on every device and in
/// every time zone. Arithmetic works on the proleptic Gregorian calendar with plain integers,
/// the same as the UTC arithmetic of the TypeScript reference (`packages/shared/src/dates.ts`),
/// so it never trips over a daylight saving change. It encodes as the bare `YYYY-MM-DD` string.
public struct LocalDate: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
  public let year: Int
  public let month: Int
  public let day: Int

  /// The day with these parts, or nil when it doesn't exist (no February 31st). Years run
  /// 0 to 9999, the four digits of the string form.
  public init?(year: Int, month: Int, day: Int) {
    guard (0...9999).contains(year), (1...12).contains(month),
      (1...Self.daysIn(month: month, year: year)).contains(day)
    else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }

  /// Reads exactly `YYYY-MM-DD` (ASCII digits only) and nothing else. Nil for anything that
  /// isn't a real day.
  public init?(_ string: String) {
    let bytes = Array(string.utf8)
    let dash = UInt8(ascii: "-")
    guard bytes.count == 10, bytes[4] == dash, bytes[7] == dash else { return nil }
    func number(_ range: Range<Int>) -> Int? {
      var value = 0
      for byte in bytes[range] {
        guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
        value = value * 10 + Int(byte - UInt8(ascii: "0"))
      }
      return value
    }
    guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10) else {
      return nil
    }
    self.init(year: year, month: month, day: day)
  }

  public var description: String {
    let year = String(self.year)
    return String(repeating: "0", count: max(0, 4 - year.count)) + year
      + "-" + (month < 10 ? "0" : "") + String(month)
      + "-" + (day < 10 ? "0" : "") + String(day)
  }

  public init(from decoder: any Decoder) throws {
    let string = try decoder.singleValueContainer().decode(String.self)
    guard let value = LocalDate(string) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "\(string) is not a real day"))
    }
    self = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  // MARK: Arithmetic

  /// The day `n` days after this one (or before, for negative `n`).
  public func adding(days n: Int) -> LocalDate {
    Self.fromEpochDay(epochDay + n)
  }

  /// Whole days from this day to `other` (negative when `other` is earlier).
  public func days(until other: LocalDate) -> Int {
    other.epochDay - epochDay
  }

  public var weekday: Weekday {
    // 1970-01-01, day 0, was a Thursday.
    Weekday(rawValue: ((epochDay % 7) + 7 + 4) % 7) ?? .sunday
  }

  /// The first day of the week this day falls in.
  public func startOfWeek(startingOn startsOn: WeekStartDay = .monday) -> LocalDate {
    adding(days: -((weekday.rawValue - startsOn.weekday.rawValue + 7) % 7))
  }

  /// The seven days of the week starting on this day.
  public func weekDays() -> [LocalDate] {
    (0..<7).map { adding(days: $0) }
  }

  // MARK: Calendar maths

  private static func isLeap(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }

  private static func daysIn(month: Int, year: Int) -> Int {
    switch month {
    case 2: isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
  }

  private init(unchecked year: Int, _ month: Int, _ day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
  private var epochDay: Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  /// The inverse of `epochDay` (`civil_from_days`).
  private static func fromEpochDay(_ days: Int) -> LocalDate {
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra =
      (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shiftedMonth = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
    let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return LocalDate(unchecked: year, month, day)
  }
}
