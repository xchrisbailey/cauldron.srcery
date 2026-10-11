import CauldronKit
import Foundation
import Testing

/// Ported case for case from `packages/shared/test/adaptive.test.ts`.
private func day(_ string: String) -> LocalDate { LocalDate(string)! }

private func close(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
  abs(a - b) <= tolerance
}

private let today = day("2026-10-21")
// The 21 day window is 2026-10-01 to 2026-10-21 inclusive.
private let windowStart = today.adding(days: -(AdaptiveLimits.windowDays - 1))
private func windowDay(_ i: Int) -> LocalDate { windowStart.adding(days: i) }

private struct Stretch {
  var intake: [IntakeCalories]
  var trend: [TrendDay]
}

/// A simulated stretch: eat `intake` a day, burn `expenditure` a day, from `startKg`.
private func simulate(
  intake: Double, expenditure: Double, startKg: Double = 80, loggedDays: [Int]? = nil,
  weighInDays: [Int]? = nil
) -> Stretch {
  let all = Array(0..<AdaptiveLimits.windowDays)
  let kgPerDay = (intake - expenditure) / 7700
  return Stretch(
    intake: (loggedDays ?? all).map { IntakeCalories(date: windowDay($0), calories: intake) },
    trend: (weighInDays ?? all).map {
      TrendDay(date: windowDay($0), trendKg: startKg + kgPerDay * Double($0))
    })
}

private let noOverrides = TargetOverrides(calories: false, protein: false, carbs: false, fat: false)
private let current = Targets(
  calories: 2200, protein: 150, carbs: 250, fat: 70, overridden: noOverrides, checkedInOn: nil)

private func estimate(
  _ stretch: Stretch, calculatorExpenditure: Double = 2800
) -> ExpenditureEstimate {
  estimateExpenditure(
    intake: stretch.intake, trend: stretch.trend, today: today,
    calculatorExpenditure: calculatorExpenditure)
}

@Suite("estimateExpenditure")
struct EstimateExpenditureTests {
  @Test func measuresASteadyLossEating2000WhileBurning2500() {
    let result = estimate(simulate(intake: 2000, expenditure: 2500))
    // Trend falls 500 / 7700 kg a day, about 0.45 kg a week
    #expect(close(result.trendChangeKg! / 20 * 7, -0.4545, within: 5e-4))
    // measured = 2000 - (-20 * 500 / 7700 * 7700) / 20 = 2500
    #expect(close(result.measured!, 2500, within: 5e-7))
    #expect(result.confidence == 1)
    #expect(result.loggedDays == 21)
    #expect(result.weighIns == 21)
    #expect(result.expenditure == 2500)
  }

  @Test func measuresAPlateauEating2400WithAFlatTrend() {
    let result = estimate(simulate(intake: 2400, expenditure: 2400), calculatorExpenditure: 2600)
    #expect(close(result.measured!, 2400, within: 5e-7))
    #expect(close(result.trendChangeKg!, 0, within: 5e-10))
    #expect(result.expenditure == 2400)
  }

  @Test func leansOnTheCalculatorWhenLoggingIsSparse() {
    let result = estimate(
      simulate(
        intake: 2000, expenditure: 2500, loggedDays: [2, 8, 12, 19], weighInDays: [0, 10, 20]))
    // confidence = 4 / 14 * 3 / 10
    let confidence = (4.0 / 14) * (3.0 / 10)
    #expect(close(result.confidence, confidence, within: 5e-10))
    #expect(result.loggedDays == 4)
    #expect(result.weighIns == 3)
    #expect(close(result.measured!, 2500, within: 5e-7))
    // 0.0857 * 2500 + 0.9143 * 2800 = 2774.3 -> 2770
    #expect(result.expenditure == 2770)
    #expect(abs(result.expenditure - 2800) < 50)
  }

  @Test func skipsUnloggedDaysInsteadOfCountingThemAsZero() {
    let full = simulate(intake: 2000, expenditure: 2500)
    let half = simulate(
      intake: 2000, expenditure: 2500, loggedDays: (0..<21).filter { $0 % 2 == 0 })
    let a = estimate(full)
    let b = estimate(half)
    #expect(b.loggedDays == 11)
    #expect(close(b.measured!, a.measured!, within: 5e-7))
    #expect(close(b.measured!, 2500, within: 5e-7))
  }

  @Test func ignoresDataOutsideTheWindow() {
    var stretch = simulate(intake: 2000, expenditure: 2500)
    stretch.intake.insert(
      IntakeCalories(date: windowStart.adding(days: -1), calories: 9000), at: 0)
    stretch.trend.insert(TrendDay(date: windowStart.adding(days: -1), trendKg: 120), at: 0)
    let result = estimate(stretch)
    #expect(result.loggedDays == 21)
    #expect(close(result.measured!, 2500, within: 5e-7))
  }

  @Test func fallsBackToTheCalculatorWithTooLittleData() {
    let full = simulate(intake: 2000, expenditure: 2500)

    // No logged days
    let noLogs = estimate(Stretch(intake: [], trend: full.trend))
    #expect(noLogs.measured == nil)
    #expect(noLogs.expenditure == 2800)
    #expect(noLogs.confidence == 0)

    // Fewer than two trend points
    let oneWeighIn = estimate(Stretch(intake: full.intake, trend: Array(full.trend.prefix(1))))
    #expect(oneWeighIn.measured == nil)
    #expect(oneWeighIn.expenditure == 2800)
    #expect(oneWeighIn.confidence == 0)
    #expect(oneWeighIn.weighIns == 1)
    #expect(oneWeighIn.trendChangeKg == nil)

    // Trend span under seven days
    let short = simulate(intake: 2000, expenditure: 2500, weighInDays: [14, 20])
    let shortSpan = estimate(Stretch(intake: full.intake, trend: short.trend))
    #expect(shortSpan.measured == nil)
    #expect(shortSpan.expenditure == 2800)
    #expect(shortSpan.confidence == 0)
    #expect(shortSpan.weighIns == 2)
  }

  @Test func roundsTheFallbackToTheNearest10() {
    let result = estimate(Stretch(intake: [], trend: []), calculatorExpenditure: 2764.3)
    #expect(result.expenditure == 2760)
  }

  @Test func acceptsASpanOfExactlySevenDays() {
    let result = estimate(simulate(intake: 2000, expenditure: 2500, weighInDays: [13, 20]))
    #expect(close(result.measured!, 2500, within: 5e-7))
    // confidence = 1 * 2 / 10
    #expect(close(result.confidence, 0.2, within: 5e-10))
  }
}

@Suite("proposeTargets")
struct ProposeTargetsTests {
  private func steady() -> ExpenditureEstimate {
    estimate(simulate(intake: 2000, expenditure: 2500))
  }

  @Test func movesTowardTheMeasuredExpenditure() {
    let proposal = proposeTargets(
      estimate: steady(), goal: .lose, weeklyRateKg: 0.5, weightKg: 80, sex: .male,
      current: current, keepOverrides: false)
    // expenditure 2500 - 550 = 1950
    #expect(proposal.targets.calories == 1950)
    #expect(close(proposal.dailyAdjustment, -550, within: 5e-7))
    #expect(proposal.floored == false)
    // protein 144 g; fat 0.25 * 1950 / 9 = 54.2 -> 54 g (above the 48 g minimum)
    #expect(proposal.targets.protein == 144)
    #expect(proposal.targets.fat == 54)
    #expect(proposal.expectedWeeklyChangeKg == -0.5)
    #expect(close(proposal.actualWeeklyChangeKg!, -0.4545, within: 5e-4))
  }

  @Test func reportsAFlatTrendAndAGainGoalWithSigns() {
    let flat = estimate(simulate(intake: 2400, expenditure: 2400), calculatorExpenditure: 2600)
    let proposal = proposeTargets(
      estimate: flat, goal: .gain, weeklyRateKg: 0.25, weightKg: 80, sex: .male,
      current: current, keepOverrides: false)
    // 2400 + 275 = 2675 -> 2680 (rounded to the nearest 10)
    #expect(proposal.targets.calories == 2680)
    #expect(proposal.expectedWeeklyChangeKg == 0.25)
    #expect(abs(proposal.actualWeeklyChangeKg!) < 1e-9)
  }

  @Test func hasNoActualChangeWhenTheTrendIsNotMeasurable() {
    let empty = estimate(Stretch(intake: [], trend: []), calculatorExpenditure: 2500)
    let proposal = proposeTargets(
      estimate: empty, goal: .maintain, weeklyRateKg: 0.5, weightKg: 80, sex: .male,
      current: current, keepOverrides: false)
    #expect(proposal.actualWeeklyChangeKg == nil)
    #expect(proposal.expectedWeeklyChangeKg == 0)
    #expect(proposal.targets.calories == 2500)
  }

  @Test func appliesTheCalorieFloor() {
    let empty = estimate(Stretch(intake: [], trend: []), calculatorExpenditure: 1400)
    let proposal = proposeTargets(
      estimate: empty, goal: .lose, weeklyRateKg: 1, weightKg: 60, sex: .female,
      current: current, keepOverrides: false)
    #expect(proposal.floored)
    #expect(proposal.targets.calories == 1200)
  }

  @Test func keepsHandSetValuesWhenAskedAndReplacesThemOtherwise() {
    var overridden = current
    overridden.protein = 200
    overridden.fat = 90
    overridden.overridden = TargetOverrides(calories: false, protein: true, carbs: false, fat: true)
    let kept = proposeTargets(
      estimate: steady(), goal: .lose, weeklyRateKg: 0.5, weightKg: 80, sex: .male,
      current: overridden, keepOverrides: true)
    #expect(kept.targets.calories == 1950)
    #expect(kept.targets.protein == 200)
    #expect(kept.targets.fat == 90)
    // carbs come from the split: (1950 - 576 - 487.5) / 4 = 221.6 -> 222
    #expect(kept.targets.carbs == 222)

    let replaced = proposeTargets(
      estimate: steady(), goal: .lose, weeklyRateKg: 0.5, weightKg: 80, sex: .male,
      current: overridden, keepOverrides: false)
    #expect(replaced.targets == MacroTargets(calories: 1950, protein: 144, carbs: 222, fat: 54))
  }

  @Test func keepsAHandSetCalorieTargetAndSplitsMacrosAroundIt() {
    var handSet = current
    handSet.calories = 2000
    handSet.overridden = TargetOverrides(calories: true, protein: false, carbs: false, fat: false)
    let proposal = proposeTargets(
      estimate: steady(), goal: .lose, weeklyRateKg: 0.5, weightKg: 80, sex: .male,
      current: handSet, keepOverrides: true)
    #expect(proposal.targets.calories == 2000)
    // protein 144 g, fat 0.25 * 2000 / 9 = 55.6 -> 56 g
    #expect(proposal.targets.protein == 144)
    #expect(proposal.targets.fat == 56)
  }
}
