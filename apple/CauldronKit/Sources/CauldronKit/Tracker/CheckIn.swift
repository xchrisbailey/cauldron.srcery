import Foundation

// The weekly check-in: what was eaten and how the weight trend moved say what the body is
// burning, and the targets are proposed again from that. This is the part that reads those
// numbers (`estimateExpenditure` and `proposeTargets` do the maths): when a check-in is due, the
// trend the estimate reads, and the estimate and proposal built from a person's data. Ported
// from `apps/web/src/lib/check-in.ts`.

public enum CheckInRules {
  /// Days between check-ins.
  public static let intervalDays = 7
  /// Days the smoothed trend needs before its changes can be trusted.
  public static let trendWarmUpDays = 14

  /// The first day the check-in looks at: the start of the estimate's window.
  public static func from(today: LocalDate) -> LocalDate {
    today.adding(days: -(AdaptiveLimits.windowDays - 1))
  }

  /// At least two weigh-ins, a week or more apart.
  public static func hasWeekOfData(_ days: [LocalDate]) -> Bool {
    guard days.count >= 2, let first = days.min(), let last = days.max() else { return false }
    return first.days(until: last) >= intervalDays
  }

  /// Whether to offer the check-in: targets and a profile, a week since the last one, and a
  /// week of weigh-ins in the estimate's window (an old pair doesn't keep offering a check-in
  /// the estimate can't use).
  public static func isDue(
    profile: BodyProfile?, targets: Targets?, weighInDays: [LocalDate], today: LocalDate
  ) -> Bool {
    guard profile != nil, let targets else { return false }
    if let last = targets.checkedInOn, last.days(until: today) < intervalDays { return false }
    let from = from(today: today)
    return hasWeekOfData(weighInDays.filter { $0 >= from && $0 <= today })
  }

  /// The trend the estimate reads. The smoothed trend starts at the first weigh-in and lags for
  /// a couple of weeks, which would understate a new cook's change; until it has warmed up, a
  /// straight-line fit through the window's weigh-ins stands in for it.
  public static func trendForEstimate(weighIns: [WeighIn], today: LocalDate) -> [TrendDay] {
    let series = trendSeries(weighIns)
    let from = from(today: today)
    guard let first = series.first, first.date.days(until: from) < trendWarmUpDays else {
      return series.map { TrendDay(date: $0.date, trendKg: $0.trendKg) }
    }
    let inWindow = series.filter { $0.date >= from && $0.date <= today }
    if inWindow.count < 2 {
      return inWindow.map { TrendDay(date: $0.date, trendKg: $0.weightKg) }
    }
    let xs = inWindow.map { Double(from.days(until: $0.date)) }
    let mx = xs.reduce(0, +) / Double(xs.count)
    let my = inWindow.reduce(0.0) { $0 + $1.weightKg } / Double(inWindow.count)
    var sxy = 0.0
    var sxx = 0.0
    for (index, point) in inWindow.enumerated() {
      sxy += (xs[index] - mx) * (point.weightKg - my)
      sxx += (xs[index] - mx) * (xs[index] - mx)
    }
    let slope = sxx == 0 ? 0 : sxy / sxx
    return inWindow.enumerated().map { index, point in
      TrendDay(date: point.date, trendKg: my + slope * (xs[index] - mx))
    }
  }
}

/// A check-in's answer: what the body seems to burn and the targets that follow from it.
public struct CheckIn: Sendable, Hashable {
  public var estimate: ExpenditureEstimate
  public var proposal: ProposedTargets
  /// Whole weeks the window covers.
  public var weeks: Int
  /// The trend weight today, which the proposal is for.
  public var weightKg: Double

  public init(
    estimate: ExpenditureEstimate, proposal: ProposedTargets, weeks: Int, weightKg: Double
  ) {
    self.estimate = estimate
    self.proposal = proposal
    self.weeks = weeks
    self.weightKg = weightKg
  }

  /// Whether the proposal is no different from the targets now.
  public func isUnchanged(from targets: Targets) -> Bool {
    proposal.targets
      == MacroTargets(
        calories: targets.calories, protein: targets.protein, carbs: targets.carbs,
        fat: targets.fat)
  }
}

/// Everything a check-in reads.
public struct CheckInInputs: Sendable, Hashable {
  public var profile: BodyProfile?
  public var targets: Targets?
  /// One weigh-in a day, oldest first, a year back.
  public var weighIns: [WeighIn]
  /// Days with something logged in the estimate's window.
  public var intake: [IntakeDay]
  public var today: LocalDate

  /// A year of weigh-ins is read, so the trend is the same as on the weight screen.
  public static let weighInDays = 365

  public init(
    profile: BodyProfile?, targets: Targets?, weighIns: [WeighIn], intake: [IntakeDay],
    today: LocalDate
  ) {
    self.profile = profile
    self.targets = targets
    self.weighIns = weighIns
    self.intake = intake
    self.today = today
  }

  public var isDue: Bool {
    CheckInRules.isDue(
      profile: profile, targets: targets, weighInDays: weighIns.map(\.date), today: today)
  }

  /// Whether any target was typed in by hand, which the cook can choose to keep.
  public var hasHandSetTargets: Bool {
    guard let overridden = targets?.overridden else { return false }
    return overridden.calories || overridden.protein || overridden.carbs || overridden.fat
  }

  /// The estimate and proposal, or nil without a profile, targets and a weigh-in.
  public func build(keepOverrides: Bool) -> CheckIn? {
    guard let profile, let targets, let latest = trendSeries(weighIns).last else { return nil }
    let weightKg = latest.trendKg
    let calculator = calculateTargets(
      CalculatorInput(
        sex: profile.sex, birthDate: profile.birthDate, heightCm: profile.heightCm,
        weightKg: weightKg, activity: profile.activity, goal: profile.goal,
        weeklyRateKg: profile.weeklyRateKg, proteinPerKg: profile.proteinPerKg,
        fatShare: profile.fatShare, today: today))
    // Only logged days count; an unlogged day is not a zero-calorie day.
    let estimate = estimateExpenditure(
      intake: intake.map { IntakeCalories(date: $0.date, calories: $0.totals.calories) },
      trend: CheckInRules.trendForEstimate(weighIns: weighIns, today: today), today: today,
      calculatorExpenditure: calculator.expenditure)
    let proposal = proposeTargets(
      estimate: estimate, goal: profile.goal, weeklyRateKg: profile.weeklyRateKg,
      weightKg: weightKg, sex: profile.sex, proteinPerKg: profile.proteinPerKg,
      fatShare: profile.fatShare, current: targets, keepOverrides: keepOverrides)
    return CheckIn(
      estimate: estimate, proposal: proposal,
      weeks: max(1, Int(jsRound(Double(estimate.windowDays) / 7))), weightKg: weightKg)
  }
}
