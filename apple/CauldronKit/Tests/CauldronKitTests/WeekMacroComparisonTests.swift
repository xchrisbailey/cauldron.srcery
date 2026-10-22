import Testing

@testable import CauldronKit

@Suite("Weekly macro comparison")
struct WeekMacroComparisonTests {
  @Test func fullWeekTargetAndRemainingIncludeEveryDay() {
    let target = MacroTargets(calories: 2_000, protein: 100, carbs: 200, fat: 70)
    let tally = MacroTally(
      totals: MacroTotals(calories: 8_000, protein: 700, carbs: 1_400, fat: 490),
      counted: 4, missing: 0, freeText: 0)
    let comparison = WeekMacroComparison(tally: tally, dailyTarget: target)
    #expect(comparison.target.calories == 14_000)
    #expect(comparison.remaining(for: .calories) == 6_000)
    #expect(comparison.remaining(for: .protein) == 0)
    #expect(comparison.isIncomplete == false)
  }

  @Test func zeroGoalsAreSafeAndUnknownMealsQualifyComparison() {
    let tally = MacroTally(totals: .zero, counted: 0, missing: 1, freeText: 1)
    let comparison = WeekMacroComparison(
      tally: tally, dailyTarget: MacroTargets(calories: 0, protein: 0, carbs: 0, fat: 0))
    #expect(comparison.progress(for: .calories) == nil)
    #expect(comparison.remaining(for: .calories) == 0)
    #expect(comparison.isIncomplete)
  }

  @Test func comparisonDistinguishesBelowExactAndOverTheFullWeekGoal() {
    let goal = MacroTargets(calories: 2_000, protein: 100, carbs: 200, fat: 70)
    func calories(_ planned: Double) -> Double {
      let tally = MacroTally(
        totals: MacroTotals(calories: planned, protein: 0, carbs: 0, fat: 0),
        counted: 1, missing: 0, freeText: 0)
      return WeekMacroComparison(tally: tally, dailyTarget: goal).remaining(for: .calories)
    }
    #expect(calories(13_000) == 1_000)
    #expect(calories(14_000) == 0)
    #expect(calories(15_000) == -1_000)
  }
}
