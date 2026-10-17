import Foundation

/// `Math.round`: halves round toward positive infinity (so -2.5 is -2), where Swift's default
/// `.rounded()` rounds them away from zero. Ported maths uses this wherever the TypeScript
/// reference rounded, so the numbers agree to the gram and calorie.
func jsRound(_ x: Double) -> Double {
  guard x.isFinite else { return x }
  let floor = x.rounded(.down)
  return x - floor >= 0.5 ? floor + 1 : floor
}

/// `Math.min(max, Math.max(min, Math.round(n)))` as a whole number. A NaN, which has no `Int`,
/// takes the lower bound.
func clampedRound(_ n: Double, to range: ClosedRange<Double>) -> Int {
  guard !n.isNaN else { return Int(range.lowerBound) }
  return Int(min(range.upperBound, max(range.lowerBound, jsRound(n))))
}
