import CauldronKit
import Testing

/// Ported from `packages/shared/test/ingredients/scale.test.ts` and `display.test.ts`.
@Suite("scaleQuantity")
struct ScaleQuantityTests {
  @Test func scalesSingleValuesAndRanges() {
    #expect(
      scaleQuantity(Quantity(min: 1.5, max: nil), by: 2) == Quantity(min: 3, max: nil))
    #expect(scaleQuantity(Quantity(min: 2, max: 3), by: 0.5) == Quantity(min: 1, max: 1.5))
  }
}

struct FormatCase: Sendable {
  let value: Double
  let unit: UnitCode?
  let expected: String
}

@Suite("formatQuantity")
struct FormatQuantityTests {
  /// US and counts use fractions.
  static let fractions: [FormatCase] = [
    .init(value: 1.5, unit: .cup, expected: "1 ½"),
    .init(value: 0.5, unit: .cup, expected: "½"),
    .init(value: 0.75, unit: .tsp, expected: "¾"),
    .init(value: 1.0 / 3, unit: .cup, expected: "⅓"),
    .init(value: 2.0 / 3, unit: .cup, expected: "⅔"),
    .init(value: 0.3333, unit: .cup, expected: "⅓"),
    .init(value: 0.25, unit: .tbsp, expected: "¼"),
    .init(value: 0.125, unit: .tsp, expected: "⅛"),
    .init(value: 2, unit: .cup, expected: "2"),
    .init(value: 2.97, unit: .cup, expected: "3"),
    .init(value: 2.98, unit: .cup, expected: "3"),
    .init(value: 3.6, unit: .cup, expected: "3 ⅝"),
    .init(value: 0.01, unit: .tsp, expected: "0.01"),
    .init(value: 0.05, unit: .tsp, expected: "0.05"),
    .init(value: 0.06, unit: .tsp, expected: "0.06"),
    .init(value: 0.07, unit: .tsp, expected: "⅛"),
    .init(value: 1.0 / 6, unit: .tsp, expected: "⅙"),
    .init(value: 5.0 / 6, unit: .cup, expected: "⅚"),
    .init(value: 0, unit: .tsp, expected: "0"),
    .init(value: 10.5, unit: .oz, expected: "10 ½"),
    .init(value: 1.49, unit: .cup, expected: "1 ½"),
    .init(value: 1.9, unit: .cup, expected: "1 ⅞"),
    .init(value: 3, unit: nil, expected: "3"),
    .init(value: 0.5, unit: nil, expected: "½"),
    .init(value: 2, unit: .clove, expected: "2"),
    .init(value: 1.25, unit: .lb, expected: "1 ¼"),
  ]

  @Test(arguments: fractions)
  func usAndCountsUseFractions(_ c: FormatCase) {
    #expect(formatQuantity(Quantity(min: c.value, max: nil), unit: c.unit) == c.expected)
  }

  @Test func formatsRangesWithAnEnDash() {
    #expect(formatQuantity(Quantity(min: 2, max: 3), unit: .clove) == "2–3")
    #expect(formatQuantity(Quantity(min: 0.5, max: 1.5), unit: .cup) == "½–1 ½")
  }

  @Test func collapsesARangeThatRoundsToOneValue() {
    #expect(formatQuantity(Quantity(min: 2, max: 2.01), unit: .cup) == "2")
  }

  /// Metric uses decimals.
  static let decimals: [FormatCase] = [
    .init(value: 250, unit: .g, expected: "250"),
    .init(value: 1.5, unit: .kg, expected: "1.5"),
    .init(value: 1.25, unit: .kg, expected: "1.25"),
    .init(value: 236.588, unit: .ml, expected: "237"),
    .init(value: 12.5, unit: .g, expected: "12.5"),
    .init(value: 12.04, unit: .g, expected: "12"),
    .init(value: 0.5, unit: .l, expected: "0.5"),
    .init(value: 4.929, unit: .ml, expected: "4.93"),
    .init(value: 2, unit: .kg, expected: "2"),
    .init(value: 0.001, unit: .g, expected: "0.001"),
  ]

  @Test(arguments: decimals)
  func metricUsesDecimals(_ c: FormatCase) {
    #expect(formatQuantity(Quantity(min: c.value, max: nil), unit: c.unit) == c.expected)
  }

  @Test func formatsMetricRanges() {
    #expect(formatQuantity(Quantity(min: 350, max: 400), unit: .g) == "350–400")
  }
}

@Suite("formatMeasure")
struct FormatMeasureTests {
  @Test func addsAUnitLabel() {
    #expect(formatMeasure(Quantity(min: 1.5, max: nil), unit: .cup) == "1 ½ c")
    #expect(formatMeasure(Quantity(min: 250, max: nil), unit: .g) == "250 g")
    #expect(formatMeasure(Quantity(min: 2, max: 3), unit: .clove) == "2–3 cloves")
    #expect(formatMeasure(Quantity(min: 1, max: nil), unit: .clove) == "1 clove")
    #expect(formatMeasure(Quantity(min: 2, max: nil), unit: nil) == "2")
  }

  @Test func stepsSmallUSVolumesDown() {
    #expect(formatMeasure(Quantity(min: 0.125, max: nil), unit: .cup) == "2 tbsp")
    #expect(formatMeasure(Quantity(min: 0.0625, max: nil), unit: .cup) == "1 tbsp")
    #expect(formatMeasure(Quantity(min: 0.5, max: nil), unit: .tbsp) == "1 ½ tsp")
    #expect(formatMeasure(Quantity(min: 1.0 / 32, max: nil), unit: .cup) == "1 ½ tsp")
    #expect(formatMeasure(Quantity(min: 0.25, max: nil), unit: .cup) == "¼ c")
    #expect(formatMeasure(Quantity(min: 1, max: nil), unit: .tbsp) == "1 tbsp")
    #expect(formatMeasure(Quantity(min: 0.0625, max: 0.125), unit: .cup) == "1–2 tbsp")
  }

  @Test func doesNotStepUpOrTouchMetricAndCounts() {
    #expect(formatMeasure(Quantity(min: 48, max: nil), unit: .tsp) == "48 tsp")
    #expect(formatMeasure(Quantity(min: 0.5, max: nil), unit: .g) == "0.5 g")
    #expect(formatMeasure(Quantity(min: 0.01, max: nil), unit: .clove) == "0.01 clove")
  }

  @Test func showsPinchBelowASixteenthOfATeaspoonAndAFractionAbove() {
    #expect(formatMeasure(Quantity(min: 0.01, max: nil), unit: .tsp) == "pinch")
    #expect(formatMeasure(Quantity(min: 0.06, max: nil), unit: .tsp) == "pinch")
    #expect(formatMeasure(Quantity(min: 0.0625, max: nil), unit: .tsp) == "⅛ tsp")
    #expect(formatMeasure(Quantity(min: 0.005, max: nil), unit: .tbsp) == "pinch")
    #expect(formatMeasure(Quantity(min: 0, max: nil), unit: .tsp) == "pinch")
  }

  @Test func doesNotInflateAScaledDownPinch() throws {
    let p = parseIngredientLine("1/4 tsp salt")
    let quantity = try #require(p.quantity)
    #expect(formatMeasure(scaleQuantity(quantity, by: 1.0 / 8), unit: p.unit) == "pinch")
    #expect(formatMeasure(scaleQuantity(quantity, by: 1.0 / 2), unit: p.unit) == "⅛ tsp")
  }
}

@Suite("parse, scale, format")
struct ParseScaleFormatTests {
  @Test func doublesAParsedLine() throws {
    let p = parseIngredientLine("1 1/2 cups flour")
    let quantity = try #require(p.quantity)
    #expect(formatQuantity(scaleQuantity(quantity, by: 2), unit: p.unit) == "3")
    #expect(formatQuantity(scaleQuantity(quantity, by: 1.0 / 3), unit: p.unit) == "½")
  }
}

/// Known conversions and scalings, as the recipe view shows them (#10).
struct DisplayMeasureCase: Sendable, CustomTestStringConvertible {
  let min: Double
  let max: Double?
  let unit: UnitCode?
  let factor: Double
  let system: UnitSystemChoice
  let amount: String
  let label: String?

  var testDescription: String {
    "\(min)\(max.map { "-\($0)" } ?? "") \(unit.map(\.rawValue) ?? "none") x\(factor) \(system) -> \(amount) \(label ?? "")"
  }
}

@Suite("displayMeasure")
struct DisplayMeasureTests {
  static let table: [DisplayMeasureCase] = [
    // As written, scaled.
    .init(min: 1, max: nil, unit: .cup, factor: 2, system: .asWritten, amount: "2", label: "c"),
    .init(
      min: 0.5, max: nil, unit: .cup, factor: 0.25, system: .asWritten, amount: "2", label: "tbsp"),
    .init(
      min: 1, max: nil, unit: .tsp, factor: 0.25, system: .asWritten, amount: "¼", label: "tsp"),
    .init(min: 350, max: nil, unit: .g, factor: 2, system: .asWritten, amount: "700", label: "g"),
    .init(
      min: 3, max: nil, unit: .clove, factor: 1.5, system: .asWritten, amount: "4 ½",
      label: "cloves"),
    .init(min: 2, max: 3, unit: .tbsp, factor: 2, system: .asWritten, amount: "4–6", label: "tbsp"),
    .init(min: 2, max: nil, unit: nil, factor: 1.5, system: .asWritten, amount: "3", label: nil),
    .init(
      min: 1, max: nil, unit: .tsp, factor: 1.0 / 32, system: .asWritten, amount: "pinch",
      label: nil),
    // US to metric, rounded to what a scale or jug shows.
    .init(min: 1, max: nil, unit: .cup, factor: 1, system: .metric, amount: "235", label: "ml"),
    .init(min: 1, max: nil, unit: .tbsp, factor: 1, system: .metric, amount: "15", label: "ml"),
    .init(min: 1, max: nil, unit: .tsp, factor: 1, system: .metric, amount: "5", label: "ml"),
    .init(min: 2, max: 3, unit: .tbsp, factor: 2, system: .metric, amount: "59–89", label: "ml"),
    .init(min: 1, max: nil, unit: .flOz, factor: 1, system: .metric, amount: "30", label: "ml"),
    .init(min: 4, max: nil, unit: .cup, factor: 1, system: .metric, amount: "945", label: "ml"),
    .init(min: 5, max: nil, unit: .cup, factor: 1, system: .metric, amount: "1.19", label: "l"),
    .init(min: 1, max: nil, unit: .lb, factor: 1, system: .metric, amount: "455", label: "g"),
    .init(min: 14, max: nil, unit: .oz, factor: 1, system: .metric, amount: "395", label: "g"),
    .init(min: 3, max: nil, unit: .lb, factor: 1, system: .metric, amount: "1.36", label: "kg"),
    // Metric to US.
    .init(min: 250, max: nil, unit: .ml, factor: 1, system: .us, amount: "1", label: "c"),
    .init(min: 1, max: nil, unit: .l, factor: 1, system: .us, amount: "1", label: "qt"),
    .init(min: 15, max: nil, unit: .ml, factor: 1, system: .us, amount: "1", label: "tbsp"),
    .init(min: 500, max: nil, unit: .g, factor: 1, system: .us, amount: "1 ⅛", label: "lb"),
    .init(min: 100, max: nil, unit: .g, factor: 1, system: .us, amount: "3 ½", label: "oz"),
    .init(min: 1.5, max: nil, unit: .kg, factor: 1, system: .us, amount: "3 ⅓", label: "lb"),
    // Scaled metric amounts round too, and step between g and kg.
    .init(
      min: 7, max: nil, unit: .g, factor: 1.0 / 3, system: .asWritten, amount: "2.5", label: "g"),
    .init(min: 15, max: nil, unit: .g, factor: 1.25, system: .asWritten, amount: "19", label: "g"),
    .init(min: 250, max: nil, unit: .ml, factor: 0.75, system: .metric, amount: "190", label: "ml"),
    .init(min: 2, max: nil, unit: .kg, factor: 1.0 / 3, system: .metric, amount: "665", label: "g"),
    .init(
      min: 2, max: nil, unit: .kg, factor: 1.0 / 3, system: .asWritten, amount: "665", label: "g"),
    .init(min: 600, max: nil, unit: .g, factor: 2, system: .asWritten, amount: "1.2", label: "kg"),
    .init(min: 4.225, max: nil, unit: .cup, factor: 1, system: .metric, amount: "1", label: "l"),
    .init(
      min: 1, max: nil, unit: .tsp, factor: 1.0 / 32, system: .metric, amount: "pinch", label: nil),
    // Already in the target system, or not convertible.
    .init(min: 200, max: nil, unit: .g, factor: 1, system: .metric, amount: "200", label: "g"),
    .init(min: 2, max: nil, unit: .cup, factor: 1, system: .us, amount: "2", label: "c"),
    .init(min: 3, max: nil, unit: .clove, factor: 1, system: .metric, amount: "3", label: "cloves"),
    .init(
      min: 1, max: nil, unit: .pinch, factor: 2, system: .metric, amount: "2", label: "pinches"),
    .init(min: 1, max: nil, unit: .can, factor: 2, system: .us, amount: "2", label: "cans"),
  ]

  @Test(arguments: table)
  func displaysTheMeasure(_ c: DisplayMeasureCase) {
    let parts = displayMeasure(
      Quantity(min: c.min, max: c.max), unit: c.unit, factor: c.factor, system: c.system)
    #expect(parts == MeasureParts(amount: c.amount, unit: c.label))
  }
}
