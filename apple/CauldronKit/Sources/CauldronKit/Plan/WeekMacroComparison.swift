/// A planned week against seven days of the cook's saved daily targets.
public struct WeekMacroComparison: Sendable, Hashable {
  public let planned: MacroTotals
  public let target: MacroTotals
  public let missing: Int
  public let freeText: Int
  private let summedEntries: Int

  public init(tally: MacroTally, dailyTarget: MacroTargets) {
    self.init(tally: tally, dailyTarget: dailyTarget, days: 7)
  }

  /// Compares a period's planned tally with the same number of days of saved daily targets.
  public init(tally: MacroTally, dailyTarget: MacroTargets, days: Int) {
    planned = tally.totals
    target = MacroTotals(
      calories: Double(dailyTarget.calories) * Double(days),
      protein: Double(dailyTarget.protein) * Double(days),
      carbs: Double(dailyTarget.carbs) * Double(days), fat: Double(dailyTarget.fat) * Double(days))
    missing = tally.missing
    freeText = tally.freeText
    summedEntries = tally.counted + tally.missing + tally.freeText
  }

  /// Positive means still available, negative means over target; numerical summation noise is zero.
  public func remaining(for key: MacroKey) -> Double {
    let difference = target[key] - planned[key]
    let scale = max(abs(target[key]), abs(planned[key]))
    let roundoff = scale.ulp * Double(max(2, summedEntries))
    return abs(difference) <= roundoff ? 0 : difference
  }

  /// A target bar must never divide by zero or expose a non-finite fill.
  public func progress(for key: MacroKey) -> Double? {
    let goal = target[key]
    guard goal > 0 else { return nil }
    return min(max(planned[key] / goal, 0), 1)
  }

  public var isIncomplete: Bool { missing > 0 || freeText > 0 }
}
