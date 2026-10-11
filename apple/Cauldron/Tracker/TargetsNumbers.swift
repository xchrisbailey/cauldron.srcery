import CauldronKit
import Foundation

// The small helpers behind the targets form: reading what was typed, showing numbers the way the
// web app does, and the weekly rates on offer. Ported from `apps/web/src/lib/targets.ts`.

enum TargetKey: CaseIterable, Hashable, Sendable {
  case calories
  case protein
  case carbs
  case fat
}

/// A number typed by hand: accepts a decimal comma. Nil when empty or not a number.
func parseNumber(_ text: String) -> Double? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  let normal = trimmed.replacing(",", with: ".", maxReplacements: 1)
  // `Double` also reads hex and "inf"; a person typed a plain decimal.
  guard normal.allSatisfy({ "0123456789.+-eE".contains($0) }), let value = Double(normal),
    value.isFinite
  else { return nil }
  return value
}

/// A number for an input: up to `digits` decimals, no trailing ".0".
func showNumber(_ value: Double, digits: Int = 1) -> String {
  // Halves round up, as `toFixed` does, where `%f` would round them to even.
  let scale = pow(10, Double(digits))
  let fixed = String(
    format: "%.\(digits)f", (value * scale).rounded(.toNearestOrAwayFromZero) / scale)
  guard let rounded = Double(fixed) else { return fixed }
  return rounded == rounded.rounded() && abs(rounded) < 1e15
    ? String(Int(rounded)) : String(rounded)
}

/// A weight in the cook's unit, to one decimal.
func showWeight(_ kg: Double, unit: WeightUnit) -> String {
  showNumber(roundWeight(fromKg(kg, unit: unit)))
}

/// A weekly rate on offer, as shown (in the cook's unit) and as stored (kilograms).
struct RateChoice: Hashable, Sendable {
  var amount: Double
  var kg: Double
}

/// Weekly rates to choose from; none when maintaining. Lose up to 1 kg (2 lb), gain up to
/// 0.5 kg (1 lb).
func rateChoices(goal: Goal, unit: WeightUnit) -> [RateChoice] {
  let amounts: [Double]
  switch (unit, goal) {
  case (_, .maintain): return []
  case (.kg, .lose): amounts = [0.25, 0.5, 0.75, 1]
  case (.kg, .gain): amounts = [0.25, 0.5]
  case (.lb, .lose): amounts = [0.5, 1, 1.5, 2]
  case (.lb, .gain): amounts = [0.5, 1]
  }
  return amounts.map {
    RateChoice(
      amount: $0, kg: min(toKg($0, unit: unit), CalculatorLimits.maxWeeklyRateKg(for: goal)))
  }
}

/// The default rate for a goal: half a kilo (or one pound) a week.
func defaultRate(goal: Goal, unit: WeightUnit) -> Double? {
  rateChoices(goal: goal, unit: unit).first { $0.amount == (unit == .kg ? 0.5 : 1) }?.amount
}

/// The choice closest to a stored rate in kilograms, as its amount.
func nearestRate(goal: Goal, unit: WeightUnit, kg: Double) -> Double? {
  rateChoices(goal: goal, unit: unit)
    .min { abs($0.kg - kg) < abs($1.kg - kg) }?.amount
}
