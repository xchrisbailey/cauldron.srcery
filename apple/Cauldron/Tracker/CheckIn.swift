import CauldronKit
import Foundation
import SwiftData

// The weekly check-in: what was eaten and how the weight trend moved say what the body is
// burning, and the targets are proposed again from that. The maths is `CauldronKit`'s
// (`estimateExpenditure`, `proposeTargets`); this gathers what it reads and decides when it is
// due. Ported from `apps/web/src/lib/check-in.ts`.

extension BodyProfileRecord {
  /// The profile as the calculator reads it; nil until it has a birth date and a height.
  var profile: BodyProfile? {
    guard let birthDate, let heightCm else { return nil }
    return BodyProfile(
      sex: sex, birthDate: birthDate, heightCm: heightCm, activity: activity, goal: goal,
      weeklyRateKg: weeklyRateKg, proteinPerKg: proteinPerKg, fatShare: fatShare,
      weightUnit: weightUnit, heightUnit: heightUnit)
  }
}

extension TargetsRecord {
  var targets: Targets {
    Targets(
      calories: calories, protein: protein, carbs: carbs, fat: fat,
      overridden: TargetOverrides(
        calories: caloriesOverridden, protein: proteinOverridden, carbs: carbsOverridden,
        fat: fatOverridden),
      checkedInOn: checkedInOn)
  }
}

enum CheckInRules {
  /// Days between check-ins.
  static let intervalDays = 7
  /// Days the smoothed trend needs before its changes can be trusted.
  static let trendWarmUpDays = 14

  /// The first day the check-in looks at: the start of the estimate's window.
  static func from(today: LocalDate) -> LocalDate {
    today.adding(days: -(AdaptiveLimits.windowDays - 1))
  }

  /// At least two weigh-ins, a week or more apart.
  static func hasWeekOfData(_ days: [LocalDate]) -> Bool {
    guard days.count >= 2, let first = days.min(), let last = days.max() else { return false }
    return first.days(until: last) >= intervalDays
  }

  /// Whether to offer the check-in: targets and a profile, a week since the last one, and a
  /// week of weigh-ins in the estimate's window (an old pair doesn't keep offering a check-in
  /// the estimate can't use).
  static func isDue(
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
  static func trendForEstimate(weighIns: [WeighIn], today: LocalDate) -> [TrendDay] {
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
struct CheckIn: Equatable {
  var estimate: ExpenditureEstimate
  var proposal: ProposedTargets
  /// Whole weeks the window covers.
  var weeks: Int
  /// The trend weight today, which the proposal is for.
  var weightKg: Double

  /// Whether the proposal is no different from the targets now.
  func isUnchanged(from targets: Targets) -> Bool {
    proposal.targets
      == MacroTargets(
        calories: targets.calories, protein: targets.protein, carbs: targets.carbs,
        fat: targets.fat)
  }
}

/// Everything a check-in reads, gathered once: the profile and targets (by the keeper rule), a
/// year of weigh-ins one a day, and the days of food in the estimate's window.
struct CheckInInputs: Equatable {
  var profile: BodyProfile?
  var targets: Targets?
  var weighIns: [WeighIn]
  /// Days with something logged in the window.
  var intake: [IntakeDay]
  var today: LocalDate

  /// A year of weigh-ins is read, so the trend is the same as on the weight screen.
  static let weighInDays = 365

  @MainActor
  static func gather(from context: ModelContext, today: LocalDate) throws -> CheckInInputs {
    let weighFrom = today.adding(days: -weighInDays).description
    let weighIns = try context.fetch(
      FetchDescriptor<WeighInRecord>(predicate: #Predicate { $0.dayKey >= weighFrom }))
    let foodFrom = CheckInRules.from(today: today).description
    let foodTo = today.description
    let meals = try context.fetch(
      FetchDescriptor<DiaryEntryRecord>(
        predicate: #Predicate { $0.dayKey >= foodFrom && $0.dayKey <= foodTo }))
    return CheckInInputs(
      profile: try context.current(BodyProfileRecord.self)?.profile,
      targets: try context.current(TargetsRecord.self)?.targets,
      weighIns: WeightHistory.weighIns(of: weighIns),
      // A meal still waiting for its numbers would count as a day of nothing eaten.
      intake: IntakeAverages.days(of: meals.filter { !$0.macrosPending }), today: today)
  }

  var isDue: Bool {
    CheckInRules.isDue(
      profile: profile, targets: targets, weighInDays: weighIns.map(\.date), today: today)
  }

  /// Whether any target was typed in by hand, which the cook can choose to keep.
  var hasHandSetTargets: Bool {
    guard let overridden = targets?.overridden else { return false }
    return overridden.calories || overridden.protein || overridden.carbs || overridden.fat
  }

  /// The estimate and proposal, or nil without a profile, targets and a weigh-in.
  func build(keepOverrides: Bool) -> CheckIn? {
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
      weeks: max(1, Int(jsRounded(Double(estimate.windowDays) / 7))), weightKg: weightKg)
  }
}

/// `Math.round` for the positive numbers here.
private func jsRounded(_ value: Double) -> Double {
  value.rounded(.toNearestOrAwayFromZero)
}

/// What the cook does with a check-in: take the proposal, or not now. Either way it is checked
/// in for today, so it isn't offered again for a week.
enum CheckInWrites {
  enum Failure: Error {
    /// There are no targets to change.
    case noTargets
  }

  /// Sets the targets to the proposal, on the same row the targets form uses. Hand-set targets
  /// stay as they are when `keepOverrides`; otherwise every target is calculated again.
  @MainActor
  static func accept(
    _ check: CheckIn, keepOverrides: Bool, today: LocalDate, in context: ModelContext
  ) throws {
    guard let row = try context.current(TargetsRecord.self) else { throw Failure.noTargets }
    row.calories = check.proposal.targets.calories
    row.protein = check.proposal.targets.protein
    row.carbs = check.proposal.targets.carbs
    row.fat = check.proposal.targets.fat
    if !keepOverrides {
      row.caloriesOverridden = false
      row.proteinOverridden = false
      row.carbsOverridden = false
      row.fatOverridden = false
    }
    row.checkedInOn = today
    try commit(context)
  }

  /// Leaves the targets alone and asks again next week.
  @MainActor
  static func dismiss(today: LocalDate, in context: ModelContext) throws {
    guard let row = try context.current(TargetsRecord.self) else { throw Failure.noTargets }
    row.checkedInOn = today
    try commit(context)
  }

  @MainActor
  private static func commit(_ context: ModelContext) throws {
    do {
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
}
