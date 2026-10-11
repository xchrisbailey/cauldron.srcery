import CauldronKit
import Foundation
import SwiftData

/// Reading and showing weights, ported from `apps/web/src/lib/weight.ts` and `targets.ts`.
enum WeightText {
  /// The lowest and highest weight to accept in `unit`, rounded so both ends are valid.
  static func limits(unit: WeightUnit) -> (min: Double, max: Double) {
    (
      (fromKg(TrackerLimits.weightKg.lowerBound, unit: unit) * 10).rounded(.up) / 10,
      (fromKg(TrackerLimits.weightKg.upperBound, unit: unit) * 10).rounded(.down) / 10
    )
  }

  /// A typed weight in `unit` as kilograms, or nil when it isn't a number in range.
  static func parse(_ text: String, unit: WeightUnit) -> Double? {
    guard let typed = parseNumber(text) else { return nil }
    let rounded = roundWeight(typed)
    let limits = limits(unit: unit)
    guard rounded >= limits.min, rounded <= limits.max else { return nil }
    return toKg(rounded, unit: unit)
  }

  /// A weight for reading, in the cook's unit: always one decimal, so 73.0 doesn't read as 73.
  static func label(kg: Double, unit: WeightUnit) -> String {
    String(format: "%.1f", roundWeight(fromKg(kg, unit: unit)))
  }

  /// A change in weight with its sign, to one decimal: "+0.4", "−1.2", "0.0".
  static func signedChange(deltaKg: Double, unit: WeightUnit) -> String {
    let value = roundWeight(fromKg(deltaKg, unit: unit))
    if value == 0 { return "0.0" }
    return "\(value > 0 ? "+" : "−")\(String(format: "%.1f", abs(value)))"
  }

  /// Evenly spaced round values covering `min` to `max`, about `target` of them.
  static func niceTicks(min: Double, max: Double, target: Int = 4) -> [Double] {
    if max <= min {
      let mid = min.rounded(.toNearestOrAwayFromZero)
      return [mid - 1, mid, mid + 1]
    }
    let rough = (max - min) / Double(target)
    let magnitude = pow(10, floor(log10(rough)))
    let step = ([1.0, 2, 5, 10].first { $0 * magnitude >= rough } ?? 10) * magnitude
    let first = floor(min / step) * step
    let last = ceil(max / step) * step
    var ticks: [Double] = []
    var value = first
    while value <= last + step / 2 {
      ticks.append((value * 1e6).rounded() / 1e6)
      value += step
    }
    return ticks
  }
}

/// The weigh-ins as the weight screen draws them: the smoothed trend, the part of it in the
/// chosen range, and how the trend has moved.
struct WeightHistory: Equatable {
  /// One a day, oldest first, with the trend as of that day.
  let series: [TrendPoint]
  let today: LocalDate

  /// The weigh-ins one a day (the keeper rule picks among duplicates).
  init(weighIns: [WeighIn], today: LocalDate) {
    series = trendSeries(weighIns)
    self.today = today
  }

  init(records: [WeighInRecord], today: LocalDate) {
    self.init(weighIns: Self.weighIns(of: records), today: today)
  }

  /// One weigh-in a day: the most recently changed row wins.
  static func weighIns(of records: [WeighInRecord]) -> [WeighIn] {
    Dictionary(grouping: records, by: \.dayKey).values.compactMap { rows in
      guard let row = Deduplication.keeper(of: rows), let day = row.day else { return nil }
      return WeighIn(date: day, weightKg: row.weightKg)
    }
    .sorted { $0.date < $1.date }
  }

  var isEmpty: Bool { series.isEmpty }

  /// The first day a range shows: its start, or the first weigh-in for "all".
  func start(of range: WeightRange) -> LocalDate {
    rangeStart(range, today: today) ?? series.first?.date ?? today
  }

  func visible(_ range: WeightRange) -> [TrendPoint] {
    let start = start(of: range)
    return series.filter { $0.date >= start }
  }

  /// The visible points, newest first, for the list.
  func list(_ range: WeightRange) -> [TrendPoint] { visible(range).reversed() }

  var trendNow: Double? { trendOn(series, date: today) }
  var weekChange: Double? { trendChange(series, days: 7, today: today) }
  var monthChange: Double? { trendChange(series, days: 30, today: today) }
}

/// What the chart draws, in the cook's unit: a dot for each weigh-in, the trend as a line, and
/// the axes. Plain values; the screen turns them into marks.
struct WeightChartData: Equatable {
  struct Point: Equatable, Identifiable {
    var day: LocalDate
    var value: Double

    var id: LocalDate { day }
  }

  let dots: [Point]
  let line: [Point]
  /// Round values covering every dot and the trend, lowest first.
  let yTicks: [Double]
  let start: LocalDate
  let end: LocalDate

  var yDomain: ClosedRange<Double> {
    (yTicks.first ?? 0)...(yTicks.last ?? 1)
  }

  init(points: [TrendPoint], unit: WeightUnit, start: LocalDate, end: LocalDate) {
    dots = points.map { Point(day: $0.date, value: fromKg($0.weightKg, unit: unit)) }
    line = points.map { Point(day: $0.date, value: fromKg($0.trendKg, unit: unit)) }
    let values = (dots + line).map(\.value)
    yTicks =
      if let low = values.min(), let high = values.max() {
        WeightText.niceTicks(min: low, max: high)
      } else {
        [0, 1]
      }
    self.start = start
    self.end = end
  }
}

/// Average daily intake over the days that have food logged.
struct IntakeAverages: Equatable {
  var days: Int
  var totals: MacroTotals

  /// Nil when no day in the range has an entry.
  init?(days: [IntakeDay]) {
    let logged = days.filter { $0.entries > 0 }
    guard !logged.isEmpty else { return nil }
    self.days = logged.count
    var sum = MacroTotals.zero
    for day in logged {
      for key in MacroKey.allCases { sum[key] += day.totals[key] }
    }
    for key in MacroKey.allCases { sum[key] /= Double(logged.count) }
    totals = sum
  }

  /// The days of `records` as the intake maths wants them, one for each day with entries.
  static func days(of records: [DiaryEntryRecord]) -> [IntakeDay] {
    Dictionary(grouping: records.compactMap { record in record.entry.map { (record, $0) } }) {
      $0.1.date
    }
    .map { day, pairs in
      IntakeDay(date: day, entries: pairs.count, totals: dayTotals(pairs.map(\.1)))
    }
    .sorted { $0.date < $1.date }
  }
}

/// Changes to weigh-ins. One a day: saving a day that has one changes that row.
enum WeightWrites {
  enum Failure: Error {
    /// A weight outside what a weight can be, or a day in the future.
    case invalid
  }

  /// Logs `kg` for `day`. A weigh-in typed here is the cook's own, even over one that came from
  /// Health, so a later check of Health leaves it alone.
  static func save(kg: Double, on day: LocalDate, today: LocalDate, in context: ModelContext)
    throws
  {
    guard kg.isFinite, TrackerLimits.weightKg.contains(kg), day <= today else {
      throw Failure.invalid
    }
    let rounded = (kg * 100).rounded() / 100
    if let row = try context.weighIn(on: day) {
      row.weightKg = rounded
      row.healthSampleID = nil
    } else {
      context.insert(WeighInRecord(day: day, weightKg: rounded))
    }
    try commit(context)
  }

  /// Removes the day's weigh-in. Returns the Health sample it came from, if any, so the next
  /// check doesn't bring it back.
  @discardableResult
  static func remove(day: LocalDate, in context: ModelContext) throws -> String? {
    guard let row = try context.weighIn(on: day) else { return nil }
    let sample = row.healthSampleID
    context.delete(row)
    try commit(context)
    return sample
  }

  private static func commit(_ context: ModelContext) throws {
    do {
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
}
