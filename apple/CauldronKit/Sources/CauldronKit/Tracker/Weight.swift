import Foundation

// Weight tracking maths: unit conversion and the smoothed trend line. Weights are stored in
// kilograms; units are a display concern. Ported from `packages/shared/src/tracker/weight.ts`.

/// Kilograms in one pound.
public let kgPerLb = 0.45359237

/// A weight in the given unit, as kilograms.
public func toKg(_ value: Double, unit: WeightUnit) -> Double {
  unit == .kg ? value : value * kgPerLb
}

/// Kilograms as a weight in the given unit.
public func fromKg(_ kg: Double, unit: WeightUnit) -> Double {
  unit == .kg ? kg : kg / kgPerLb
}

/// Round to one decimal place, the precision the scale and the UI use.
public func roundWeight(_ value: Double) -> Double {
  jsRound(value * 10) / 10
}

private let cmPerInch = 2.54

public struct FeetInches: Sendable, Hashable {
  public var feet: Int
  public var inches: Double

  public init(feet: Int, inches: Double) {
    self.feet = feet
    self.inches = inches
  }
}

/// Centimetres as feet and inches (inches to one decimal, never 12).
public func cmToFeetInches(_ cm: Double) -> FeetInches {
  let totalInches = cm / cmPerInch
  // Not a number or beyond any height: nothing sensible to carry, and `Int` would trap.
  guard totalInches.isFinite, abs(totalInches) < 1e12 else { return FeetInches(feet: 0, inches: 0) }
  var feet = Int((totalInches / 12).rounded(.down))
  var inches = jsRound((totalInches - Double(feet) * 12) * 10) / 10
  if inches >= 12 {
    feet += 1
    inches = 0
  }
  return FeetInches(feet: feet, inches: inches)
}

/// Feet and inches as centimetres.
public func feetInchesToCm(feet: Double, inches: Double) -> Double {
  (feet * 12 + inches) * cmPerInch
}

/// A weigh-in with the smoothed trend as of that day.
public struct TrendPoint: Sendable, Hashable {
  public var date: LocalDate
  public var weightKg: Double
  public var trendKg: Double

  public init(date: LocalDate, weightKg: Double, trendKg: Double) {
    self.date = date
    self.weightKg = weightKg
    self.trendKg = trendKg
  }
}

/// How far the trend moves toward each new weight, per day (Hacker's Diet).
public let trendSmoothing = 0.1

/// The exponentially smoothed trend for each weigh-in, oldest first. Duplicate days keep the
/// last entry given. A gap of `n` days uses `1 - (1 - alpha)^n`, so a missed week counts as a
/// week of smoothing rather than one step.
public func trendSeries(_ weighIns: [WeighIn]) -> [TrendPoint] {
  var byDate: [LocalDate: Double] = [:]
  for weighIn in weighIns { byDate[weighIn.date] = weighIn.weightKg }

  var out: [TrendPoint] = []
  var previous: LocalDate?
  var trend = 0.0
  for date in byDate.keys.sorted() {
    guard let weightKg = byDate[date] else { continue }
    if let previous {
      let alpha = 1 - pow(1 - trendSmoothing, Double(previous.days(until: date)))
      trend += alpha * (weightKg - trend)
    } else {
      trend = weightKg
    }
    out.append(TrendPoint(date: date, weightKg: weightKg, trendKg: trend))
    previous = date
  }
  return out
}

/// The trend on `date`: the last point at or before it, or nil if none.
public func trendOn(_ series: [TrendPoint], date: LocalDate) -> Double? {
  var found: Double?
  for point in series {
    if point.date > date { break }
    found = point.trendKg
  }
  return found
}

/// How much the trend moved over the last `days` days, or nil without data.
public func trendChange(_ series: [TrendPoint], days: Int, today: LocalDate) -> Double? {
  guard let now = trendOn(series, date: today),
    let before = trendOn(series, date: today.adding(days: -days))
  else { return nil }
  return now - before
}

public enum WeightRange: String, Sendable, Hashable, Codable, CaseIterable {
  case oneMonth = "1m"
  case threeMonths = "3m"
  case oneYear = "1y"
  case all
}

/// The first day a chart range covers, or nil for all time.
public func rangeStart(_ range: WeightRange, today: LocalDate) -> LocalDate? {
  switch range {
  case .oneMonth: today.adding(days: -30)
  case .threeMonths: today.adding(days: -91)
  case .oneYear: today.adding(days: -365)
  case .all: nil
  }
}
