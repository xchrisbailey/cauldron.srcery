// Scaling and showing a quantity (`ingredients/scale.ts`).

/// Multiply a quantity (and both ends of a range) by `factor`.
public func scaleQuantity(_ quantity: Quantity, by factor: Double) -> Quantity {
  Quantity(min: quantity.min * factor, max: quantity.max.map { $0 * factor })
}

// Fractions a cook can measure, as (value, glyph). Zero and one are the whole-number edges.
private let fractions: [(value: Double, glyph: String)] = [
  (0, ""),
  (1.0 / 8, "⅛"),
  (1.0 / 6, "⅙"),
  (1.0 / 4, "¼"),
  (1.0 / 3, "⅓"),
  (3.0 / 8, "⅜"),
  (1.0 / 2, "½"),
  (5.0 / 8, "⅝"),
  (2.0 / 3, "⅔"),
  (3.0 / 4, "¾"),
  (5.0 / 6, "⅚"),
  (7.0 / 8, "⅞"),
  (1, ""),
]

/// "1 ½", "¾", "2": nearest measurable fraction. Amounts below 1/16, which would round up to ⅛
/// and inflate the amount, show as a decimal instead. Positive values never display as 0.
private func formatFraction(_ value: Double) -> String {
  if value <= 0 { return "0" }
  if value < 1.0 / 16 { return formatDecimal(value) }
  var whole = value.rounded(.down)
  let rest = value - whole
  var best = fractions[0]
  for f in fractions where abs(f.value - rest) < abs(best.value - rest) { best = f }
  if best.value == 1 { whole += 1 }
  if best.value == 0 || best.value == 1 { return whole == 0 ? "⅛" : jsString(whole) }
  return whole == 0 ? best.glyph : "\(jsString(whole)) \(best.glyph)"
}

/// 250, 1.5, 12.5, 0.25: trimmed, with precision that shrinks as the value grows.
private func formatDecimal(_ value: Double) -> String {
  let digits = value >= 100 ? 0 : value >= 10 ? 1 : 2
  let text = jsToFixed(value, digits)
  var trimmed = text
  if digits != 0 {
    while trimmed.hasSuffix("0") { trimmed.removeLast() }
    if trimmed.hasSuffix(".") { trimmed.removeLast() }
  }
  return trimmed == "0" && value > 0 ? jsString(jsRoundedToOneDigit(value)) : trimmed
}

/// Display text for the quantity only. Metric units get decimals, everything else (US units,
/// pinch, counts, no unit) gets fractions. Ranges use an en dash: "2–3".
public func formatQuantity(_ quantity: Quantity, unit: UnitCode?) -> String {
  func one(_ value: Double) -> String {
    unit?.system == .metric ? formatDecimal(value) : formatFraction(value)
  }
  let min = one(quantity.min)
  guard let max = quantity.max else { return min }
  let top = one(max)
  return min == top ? min : "\(min)–\(top)"
}

private let pinchMl = UnitCode.tsp.factor / 16

/// A measure split for display: the amount, and the unit label (nil for bare counts).
public struct MeasureParts: Sendable, Hashable {
  public var amount: String
  public var unit: String?

  public init(amount: String, unit: String?) {
    self.amount = amount
    self.unit = unit
  }
}

/// Quantity and unit label: "1 ½" + "c", "250" + "g", "2–3" + "cloves". Small US volumes step
/// down first (1/8 cup is "2 tbsp", 1/2 tbsp is "1 ½ tsp"), and anything below 1/16 tsp reads
/// "pinch" rather than an amount.
public func measureParts(_ quantity: Quantity, unit: UnitCode?) -> MeasureParts {
  guard let unit else {
    return MeasureParts(amount: formatQuantity(quantity, unit: nil), unit: nil)
  }
  var q = quantity
  var u = unit
  if unit.dimension == .volume && unit.system == .us && unit != .pinch && unit != .dash {
    let top = quantity.max ?? quantity.min
    if top * unit.factor < pinchMl {
      return MeasureParts(amount: Copy.quantities.pinch.text, unit: nil)
    }
    let next = convertForDisplay(top, unit: unit, target: .us).unit
    if next != unit {
      u = next
      q = Quantity(
        min: (quantity.min * unit.factor) / next.factor,
        max: quantity.max.map { ($0 * unit.factor) / next.factor })
    }
  }
  let top = q.max ?? q.min
  return MeasureParts(
    amount: formatQuantity(q, unit: u), unit: u.abbreviation ?? (top > 1 ? u.plural : u.singular))
}

/// Quantity plus unit label as one string: "1 ½ c", "250 g", "2–3 cloves".
public func formatMeasure(_ quantity: Quantity, unit: UnitCode?) -> String {
  let parts = measureParts(quantity, unit: unit)
  guard let label = parts.unit else { return parts.amount }
  return "\(parts.amount) \(label)"
}

/// How a recipe's units are shown: as the author wrote them, or converted.
public enum UnitSystemChoice: String, Sendable, Hashable, Codable, CaseIterable {
  case asWritten
  case metric
  case us
}

/// An ingredient amount scaled by `factor` and shown in `system`. Volumes and masses convert
/// within their dimension (never cups to grams); counts stay as written. Amounts below a
/// pinch read "pinch" in every system. Grams and millilitres that were scaled or converted
/// round to what a scale or jug shows, stepping up to kg or l from 1000.
public func displayMeasure(
  _ quantity: Quantity, unit: UnitCode?, factor: Double, system: UnitSystemChoice
) -> MeasureParts {
  let scaled = scaleQuantity(quantity, by: factor)
  guard let unit else { return measureParts(scaled, unit: nil) }
  let top = scaled.max ?? scaled.min
  if unit.dimension == .volume && unit != .pinch && unit != .dash && top * unit.factor < pinchMl {
    return MeasureParts(amount: Copy.quantities.pinch.text, unit: nil)
  }
  let target: UnitCode
  switch system {
  case .asWritten: target = unit
  case .metric: target = convertForDisplay(top, unit: unit, target: .metric).unit
  case .us: target = convertForDisplay(top, unit: unit, target: .us).unit
  }
  let metric = target.system == .metric
  if target == unit && !(metric && factor != 1) { return measureParts(scaled, unit: unit) }
  if metric {
    // Through grams or millilitres (factor 1), rounded, then kg or l when large.
    let (small, large): (UnitCode, UnitCode) = unit.dimension == .volume ? (.ml, .l) : (.g, .kg)
    let min = roundMetric(scaled.min * unit.factor)
    let max = scaled.max.map { roundMetric($0 * unit.factor) }
    if (max ?? min) >= 1000 {
      return measureParts(Quantity(min: min / 1000, max: max.map { $0 / 1000 }), unit: large)
    }
    return measureParts(Quantity(min: min, max: max), unit: small)
  }
  let ratio = unit.factor / target.factor
  return measureParts(
    Quantity(min: scaled.min * ratio, max: scaled.max.map { $0 * ratio }), unit: target)
}

/// 237 → 235, 59.1 → 59, 4.93 → 5: steps of 5 from 100, whole numbers from 10, halves below.
private func roundMetric(_ value: Double) -> Double {
  if value >= 100 { return jsRound(value / 5) * 5 }
  if value >= 10 { return jsRound(value) }
  return jsMax(0.5, jsRound(value * 2) / 2)
}
