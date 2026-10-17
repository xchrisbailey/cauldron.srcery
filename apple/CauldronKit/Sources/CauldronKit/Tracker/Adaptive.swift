import Foundation

// Adaptive targets from what was actually logged: average intake over a recent window minus
// the energy the weight trend says was stored or burned gives a measured expenditure, blended
// with the calculator's estimate by how much data there is. Ported from
// `packages/shared/src/tracker/adaptive.ts`.

/// Calories logged on a day. Callers pass only days with something logged.
public struct IntakeCalories: Sendable, Hashable {
  public var date: LocalDate
  public var calories: Double

  public init(date: LocalDate, calories: Double) {
    self.date = date
    self.calories = calories
  }
}

/// Trend weight on a day (from weigh-ins); may have gaps.
public struct TrendDay: Sendable, Hashable {
  public var date: LocalDate
  public var trendKg: Double

  public init(date: LocalDate, trendKg: Double) {
    self.date = date
    self.trendKg = trendKg
  }
}

public enum AdaptiveLimits {
  /// Days in the measurement window, ending today.
  public static let windowDays = 21
  /// Minimum days between the first and last trend points in the window.
  public static let minTrendSpanDays = 7
  public static let fullConfidenceLoggedDays = 14
  public static let fullConfidenceWeighIns = 10
}

public struct ExpenditureEstimate: Sendable, Hashable {
  /// Energy balance measurement, or nil when there is too little data.
  public var measured: Double?
  /// Measured and calculator values blended by confidence, to the nearest 10.
  public var expenditure: Double
  /// 0 to 1.
  public var confidence: Double
  public var loggedDays: Int
  public var weighIns: Int
  public var windowDays: Int
  /// Last minus first trend weight in the window, nil when not measurable.
  public var trendChangeKg: Double?
  /// Days between the first and last trend points used, nil when not measurable.
  public var spanDays: Int?
}

private func roundTo10(_ n: Double) -> Double { jsRound(n / 10) * 10 }

/// Estimate daily expenditure from logged intake and trend weight.
public func estimateExpenditure(
  intake: [IntakeCalories], trend: [TrendDay], today: LocalDate, calculatorExpenditure: Double
) -> ExpenditureEstimate {
  let windowDays = AdaptiveLimits.windowDays
  let start = today.adding(days: -(windowDays - 1))
  func inWindow(_ date: LocalDate) -> Bool { date >= start && date <= today }

  // One entry per day: a repeated date keeps its last value. The days keep the order they
  // first appeared in, as a JavaScript `Map` does, so the average adds up in the same order.
  var loggedOrder: [LocalDate] = []
  var loggedByDay: [LocalDate: Double] = [:]
  for day in intake where inWindow(day.date) {
    if loggedByDay.updateValue(day.calories, forKey: day.date) == nil {
      loggedOrder.append(day.date)
    }
  }
  var trendByDay: [LocalDate: Double] = [:]
  for point in trend where inWindow(point.date) { trendByDay[point.date] = point.trendKg }

  let loggedDays = loggedByDay.count
  let sortedTrend = trendByDay.sorted { $0.key < $1.key }
  let weighIns = sortedTrend.count

  let first = sortedTrend.first
  let last = sortedTrend.last
  let spanDays = first.flatMap { first in last.map { first.key.days(until: $0.key) } }

  guard loggedDays > 0, let first, let last, weighIns >= 2, let spanDays,
    spanDays >= AdaptiveLimits.minTrendSpanDays
  else {
    let trendChangeKg: Double? =
      if let first, let last, weighIns >= 2 { last.value - first.value } else { nil }
    return ExpenditureEstimate(
      measured: nil, expenditure: roundTo10(calculatorExpenditure), confidence: 0,
      loggedDays: loggedDays, weighIns: weighIns, windowDays: windowDays,
      trendChangeKg: trendChangeKg, spanDays: weighIns >= 2 ? spanDays : nil)
  }

  let averageIntake =
    loggedOrder.reduce(0.0) { $0 + (loggedByDay[$1] ?? 0) } / Double(loggedDays)
  let trendChangeKg = last.value - first.value
  let measured = averageIntake - (trendChangeKg * CalculatorLimits.kcalPerKg) / Double(spanDays)
  let confidence =
    min(1, Double(loggedDays) / Double(AdaptiveLimits.fullConfidenceLoggedDays))
    * min(1, Double(weighIns) / Double(AdaptiveLimits.fullConfidenceWeighIns))

  return ExpenditureEstimate(
    measured: measured,
    expenditure: roundTo10(confidence * measured + (1 - confidence) * calculatorExpenditure),
    confidence: confidence, loggedDays: loggedDays, weighIns: weighIns, windowDays: windowDays,
    trendChangeKg: trendChangeKg, spanDays: spanDays)
}

public struct ProposedTargets: Sendable, Hashable {
  public var targets: MacroTargets
  /// True when the calorie floor raised the target.
  public var floored: Bool
  /// Signed kcal per day from the goal, negative to lose.
  public var dailyAdjustment: Double
  /// What the goal asks for, signed (negative to lose, 0 to maintain).
  public var expectedWeeklyChangeKg: Double
  /// What the trend shows per week, nil when not measurable.
  public var actualWeeklyChangeKg: Double?
}

/// Propose new targets from an expenditure estimate, optionally keeping hand-set values.
public func proposeTargets(
  estimate: ExpenditureEstimate, goal: Goal, weeklyRateKg: Double, weightKg: Double, sex: Sex,
  proteinPerKg: Double? = nil, fatShare: Double? = nil, current: Targets, keepOverrides: Bool
) -> ProposedTargets {
  let rate = clampWeeklyRate(weeklyRateKg, for: goal)
  let goalResult = goalCalories(
    sex: sex, expenditure: estimate.expenditure, goal: goal, weeklyRateKg: weeklyRateKg)

  // A hand-set calorie target stays the basis for the macro split.
  let keepCalories = keepOverrides && current.overridden.calories
  let split = splitMacros(
    calories: Double(keepCalories ? current.calories : goalResult.calories), weightKg: weightKg,
    proteinPerKg: proteinPerKg, fatShare: fatShare)
  func keep(_ field: KeyPath<TargetOverrides, Bool>) -> Bool {
    keepOverrides && current.overridden[keyPath: field]
  }

  let actualWeeklyChangeKg: Double? =
    if let change = estimate.trendChangeKg, let span = estimate.spanDays, span > 0 {
      change / Double(span) * 7
    } else {
      nil
    }
  return ProposedTargets(
    targets: MacroTargets(
      calories: keep(\.calories) ? current.calories : split.calories,
      protein: keep(\.protein) ? current.protein : split.protein,
      carbs: keep(\.carbs) ? current.carbs : split.carbs,
      fat: keep(\.fat) ? current.fat : split.fat),
    floored: goalResult.floored, dailyAdjustment: goalResult.dailyAdjustment,
    expectedWeeklyChangeKg: goal == .lose ? -rate : rate,
    actualWeeklyChangeKg: actualWeeklyChangeKg)
}
