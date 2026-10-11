import CauldronKit
import Foundation
import Testing

/// Ported case for case from `packages/shared/test/dates.test.ts`.
private func day(_ string: String) -> LocalDate { LocalDate(string)! }

private func days(_ strings: [String]) -> [LocalDate] { strings.map(day) }

struct AddDaysCase: Sendable {
  let start: String
  let n: Int
  let expected: String
}

@Suite("adding(days:)")
struct AddDaysTests {
  static let cases: [AddDaysCase] = [
    .init(start: "2026-10-01", n: 0, expected: "2026-10-01"),
    .init(start: "2026-10-01", n: 1, expected: "2026-10-02"),
    .init(start: "2026-10-01", n: -1, expected: "2026-09-30"),
    .init(start: "2026-01-31", n: 1, expected: "2026-02-01"),
    .init(start: "2026-02-28", n: 1, expected: "2026-03-01"),
    .init(start: "2026-12-31", n: 1, expected: "2027-01-01"),
    .init(start: "2027-01-01", n: -1, expected: "2026-12-31"),
    .init(start: "2028-02-28", n: 1, expected: "2028-02-29"),
    .init(start: "2028-02-29", n: 1, expected: "2028-03-01"),
    .init(start: "2028-03-01", n: -1, expected: "2028-02-29"),
    .init(start: "2028-02-29", n: 365, expected: "2029-02-28"),
    .init(start: "2026-01-01", n: 365, expected: "2027-01-01"),
    .init(start: "2028-01-01", n: 366, expected: "2029-01-01"),
    .init(start: "2026-10-01", n: 30, expected: "2026-10-31"),
    .init(start: "2026-10-01", n: -400, expected: "2025-08-27"),
  ]

  @Test("adds days across months, years and leap days", arguments: cases)
  func adds(_ c: AddDaysCase) {
    #expect(day(c.start).adding(days: c.n) == day(c.expected))
    #expect(day(c.start).adding(days: c.n).description == c.expected)
  }

  @Test func stepsOneDayAtATimeOverTheUSSpringForwardDay() {
    #expect(day("2026-03-07").adding(days: 1) == day("2026-03-08"))
    #expect(day("2026-03-08").adding(days: 1) == day("2026-03-09"))
    #expect(day("2026-03-07").adding(days: 2) == day("2026-03-09"))
    #expect(day("2026-03-09").adding(days: -2) == day("2026-03-07"))
  }

  @Test func stepsOneDayAtATimeOverTheEUFallBackDay() {
    #expect(day("2026-10-24").adding(days: 1) == day("2026-10-25"))
    #expect(day("2026-10-25").adding(days: 1) == day("2026-10-26"))
    #expect(day("2026-10-26").adding(days: -2) == day("2026-10-24"))
  }

  @Test func roundTrips() {
    for string in ["2026-03-08", "2026-10-25", "2028-02-29", "2026-12-31"] {
      #expect(day(string).adding(days: 17).adding(days: -17) == day(string))
    }
  }
}

struct WeekdayCase: Sendable {
  let day: String
  let expected: Int
}

@Suite("weekday")
struct WeekdayTests {
  static let cases: [WeekdayCase] = [
    .init(day: "2026-10-04", expected: 0),
    .init(day: "2026-10-05", expected: 1),
    .init(day: "2026-10-01", expected: 4),
    .init(day: "2026-10-03", expected: 6),
    .init(day: "2028-02-29", expected: 2),
    .init(day: "2026-03-08", expected: 0),
    .init(day: "2026-10-25", expected: 0),
    .init(day: "2000-01-01", expected: 6),
  ]

  @Test("is 0 for Sunday to 6 for Saturday", arguments: cases)
  func weekday(_ c: WeekdayCase) {
    #expect(day(c.day).weekday.rawValue == c.expected)
  }
}

@Suite("startOfWeek")
struct StartOfWeekTests {
  @Test func defaultsToMonday() {
    #expect(day("2026-10-01").startOfWeek() == day("2026-09-28"))
  }

  @Test func returnsTheDayItselfWhenItIsAlreadyTheFirstDay() {
    #expect(day("2026-10-05").startOfWeek(startingOn: .monday) == day("2026-10-05"))
    #expect(day("2026-10-04").startOfWeek(startingOn: .sunday) == day("2026-10-04"))
  }

  @Test func mondayStartPutsSundayInTheWeekThatBeganSixDaysEarlier() {
    #expect(day("2026-10-04").startOfWeek(startingOn: .monday) == day("2026-09-28"))
    #expect(day("2026-10-03").startOfWeek(startingOn: .monday) == day("2026-09-28"))
  }

  @Test func sundayStartFollowsTheSundayBefore() {
    #expect(day("2026-10-05").startOfWeek(startingOn: .sunday) == day("2026-10-04"))
    #expect(day("2026-10-10").startOfWeek(startingOn: .sunday) == day("2026-10-04"))
    #expect(day("2026-10-11").startOfWeek(startingOn: .sunday) == day("2026-10-11"))
  }

  @Test func crossesMonthAndYearBoundaries() {
    #expect(day("2026-03-01").startOfWeek(startingOn: .monday) == day("2026-02-23"))
    #expect(day("2027-01-01").startOfWeek(startingOn: .monday) == day("2026-12-28"))
    #expect(day("2027-01-01").startOfWeek(startingOn: .sunday) == day("2026-12-27"))
  }

  @Test func handlesTheLeapDay() {
    #expect(day("2028-02-29").startOfWeek(startingOn: .monday) == day("2028-02-28"))
    #expect(day("2028-02-29").startOfWeek(startingOn: .sunday) == day("2028-02-27"))
    #expect(day("2028-03-05").startOfWeek(startingOn: .monday) == day("2028-02-28"))
  }

  @Test func handlesTheDSTChangeWeeks() {
    // 2026-03-08 (US) and 2026-10-25 (EU) are both Sundays.
    #expect(day("2026-03-08").startOfWeek(startingOn: .monday) == day("2026-03-02"))
    #expect(day("2026-03-08").startOfWeek(startingOn: .sunday) == day("2026-03-08"))
    #expect(day("2026-03-09").startOfWeek(startingOn: .monday) == day("2026-03-09"))
    #expect(day("2026-10-25").startOfWeek(startingOn: .monday) == day("2026-10-19"))
    #expect(day("2026-10-25").startOfWeek(startingOn: .sunday) == day("2026-10-25"))
    #expect(day("2026-10-26").startOfWeek(startingOn: .sunday) == day("2026-10-25"))
  }

  @Test func alwaysLandsOnTheRequestedWeekdayAtMostSixDaysBack() {
    var current = day("2026-02-20")
    for _ in 0..<400 {
      for startsOn in [WeekStartDay.sunday, .monday] {
        let start = current.startOfWeek(startingOn: startsOn)
        #expect(start.weekday.rawValue == startsOn.rawValue)
        let back = start.days(until: current)
        #expect(back >= 0)
        #expect(back <= 6)
      }
      current = current.adding(days: 1)
    }
  }
}

@Suite("weekDays")
struct WeekDaysTests {
  @Test func listsSevenConsecutiveDays() {
    #expect(
      day("2026-09-28").weekDays()
        == days([
          "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03",
          "2026-10-04",
        ]))
  }

  @Test func crossesAYearBoundary() {
    #expect(
      day("2026-12-28").weekDays()
        == days([
          "2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02",
          "2027-01-03",
        ]))
  }

  @Test func includesTheLeapDay() {
    let week = day("2028-02-28").weekDays()
    #expect(week.contains(day("2028-02-29")))
    #expect(week[2] == day("2028-03-01"))
  }

  @Test func hasNoGapsOrRepeatsInTheDSTChangeWeeks() {
    #expect(
      day("2026-03-02").weekDays()
        == days([
          "2026-03-02", "2026-03-03", "2026-03-04", "2026-03-05", "2026-03-06", "2026-03-07",
          "2026-03-08",
        ]))
    #expect(
      day("2026-10-19").weekDays()
        == days([
          "2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24",
          "2026-10-25",
        ]))
    #expect(day("2026-10-25").weekDays()[6] == day("2026-10-31"))
  }
}

struct DaysBetweenCase: Sendable {
  let a: String
  let b: String
  let expected: Int
}

@Suite("days(until:)")
struct DaysBetweenTests {
  static let cases: [DaysBetweenCase] = [
    .init(a: "2026-10-01", b: "2026-10-01", expected: 0),
    .init(a: "2026-10-01", b: "2026-10-08", expected: 7),
    .init(a: "2026-10-08", b: "2026-10-01", expected: -7),
    .init(a: "2026-12-31", b: "2027-01-01", expected: 1),
    .init(a: "2028-02-28", b: "2028-03-01", expected: 2),
    .init(a: "2027-02-28", b: "2027-03-01", expected: 1),
    .init(a: "2026-01-01", b: "2027-01-01", expected: 365),
    .init(a: "2028-01-01", b: "2029-01-01", expected: 366),
    .init(a: "2026-03-07", b: "2026-03-09", expected: 2),
    .init(a: "2026-03-02", b: "2026-03-09", expected: 7),
    .init(a: "2026-10-24", b: "2026-10-26", expected: 2),
    .init(a: "2026-10-19", b: "2026-10-26", expected: 7),
  ]

  @Test("counts whole days, negative when the second is earlier", arguments: cases)
  func between(_ c: DaysBetweenCase) {
    #expect(day(c.a).days(until: day(c.b)) == c.expected)
  }

  @Test func isTheInverseOfAddingDays() {
    for string in ["2026-03-08", "2026-10-25", "2028-02-29"] {
      for n in [-40, -1, 0, 1, 7, 90] {
        #expect(day(string).days(until: day(string).adding(days: n)) == n)
      }
    }
  }
}

/// What the TypeScript `isRealDate` and the `LocalDate` schema guard, and how a day is stored.
@Suite("LocalDate value")
struct LocalDateValueTests {
  @Test func readsOnlyRealYYYYMMDDDays() {
    #expect(LocalDate("2026-10-01") != nil)
    #expect(LocalDate("2028-02-29") != nil)
    #expect(LocalDate("0000-01-01") != nil)
    for bad in [
      "2026-02-31", "2027-02-29", "2026-13-01", "2026-00-10", "2026-10-00", "2026-10-32",
      "2026-1-01", "2026-10-1", "26-10-01", "20261001", "2026-10-01T00:00:00Z", " 2026-10-01",
      "2026-10-01 ", "", "tomorrow", "٢٠٢٦-١٠-٠١",
    ] {
      #expect(LocalDate(bad) == nil, "\(bad) should not parse")
    }
  }

  @Test func exposesItsParts() {
    let value = day("2028-02-29")
    #expect(value.year == 2028)
    #expect(value.month == 2)
    #expect(value.day == 29)
  }

  @Test func buildsFromPartsOnlyWhenTheDayExists() {
    #expect(LocalDate(year: 2026, month: 10, day: 1) == day("2026-10-01"))
    #expect(LocalDate(year: 2026, month: 2, day: 29) == nil)
    #expect(LocalDate(year: 2026, month: 0, day: 1) == nil)
    #expect(LocalDate(year: 10_000, month: 1, day: 1) == nil)
  }

  @Test func printsAsAPaddedYYYYMMDD() {
    #expect(day("0042-01-09").description == "0042-01-09")
    #expect(day("2026-10-01").description == "2026-10-01")
  }

  @Test func ordersChronologically() {
    #expect(day("2026-09-30") < day("2026-10-01"))
    #expect(day("2026-12-31") < day("2027-01-01"))
    #expect(
      days(["2027-01-01", "2026-10-01", "2026-09-30"]).sorted()
        == days(["2026-09-30", "2026-10-01", "2027-01-01"]))
  }

  @Test func encodesAsTheBareDayString() throws {
    let encoded = try JSONEncoder().encode([day("2026-10-01")])
    #expect(String(decoding: encoded, as: UTF8.self) == #"["2026-10-01"]"#)
    let decoded = try JSONDecoder().decode([LocalDate].self, from: encoded)
    #expect(decoded == [day("2026-10-01")])
  }

  @Test func refusesToDecodeAnImpossibleDay() {
    let json = Data(#"["2026-02-31"]"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode([LocalDate].self, from: json) }
  }
}
