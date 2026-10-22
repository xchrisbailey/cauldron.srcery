/// A planned week against seven days of the cook's saved daily targets.
public struct WeekMacroComparison: Sendable, Hashable {
  public let planned: MacroTotals
  public let target: MacroTotals
  public let missing: Int
  public let freeText: Int

  public init(tally: MacroTally, dailyTarget: MacroTargets) {
    planned = tally.totals
    target = MacroTotals(
      calories: Double(dailyTarget.calories * 7), protein: Double(dailyTarget.protein * 7),
      carbs: Double(dailyTarget.carbs * 7), fat: Double(dailyTarget.fat * 7))
    missing = tally.missing
    freeText = tally.freeText
  }

  /// Positive means still available, negative means over target; exactly met is zero.
  public func remaining(for key: MacroKey) -> Double { target[key] - planned[key] }

  /// A target bar must never divide by zero or expose a non-finite fill.
  public func progress(for key: MacroKey) -> Double? {
    let goal = target[key]
    guard goal > 0 else { return nil }
    return min(max(planned[key] / goal, 0), 1)
  }

  public var isIncomplete: Bool { missing > 0 || freeText > 0 }
}
