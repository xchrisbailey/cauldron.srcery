import CauldronKit
import Foundation
import Testing

/// `toBeCloseTo(expected, digits)`.
func toBeCloseTo(_ received: Double, _ expected: Double, digits: Int = 2) -> Bool {
  abs(expected - received) < pow(10, -Double(digits)) / 2
}

/// Ported from `packages/shared/test/ingredients/units.test.ts`. Its `schemas` block is split
/// between `Domain/IngredientTests.swift` (quantity validity) and the JSON test at the end of
/// this file (unit codes and parser output).
@Suite("Unit catalogue")
struct CatalogueTests {
  @Test func hasUniqueAliases() {
    var seen: [String: UnitCode] = [:]
    for code in UnitCode.allCases {
      for alias in code.aliases + code.caseSensitiveAliases {
        #expect(seen[alias] == nil, "\(alias) on \(code)")
        seen[alias] = code
      }
    }
  }

  @Test(
    arguments: [
      ("T", UnitCode.tbsp), ("t", .tsp), ("Tbsp.", .tbsp), ("tablespoons", .tbsp),
      ("TSP", .tsp), ("c.", .cup), ("C", .cup), ("lbs", .lb), ("grams", .g),
      ("Fl. Oz.", .flOz), ("fluid ounces", .flOz), ("oz", .oz), ("cloves", .clove),
    ])
  func looksUpAUnit(word: String, code: UnitCode) {
    #expect(lookupUnit(word) == code)
  }

  @Test(arguments: ["", "flour", "large", "x"])
  func lookupIsNilForNonUnits(word: String) {
    #expect(lookupUnit(word) == nil)
  }
}

@Suite("convert")
struct ConvertTests {
  @Test func convertsVolume() throws {
    #expect(toBeCloseTo(try #require(convert(1, from: .cup, to: .ml)), 236.588, digits: 2))
    #expect(toBeCloseTo(try #require(convert(3, from: .tsp, to: .tbsp)), 1, digits: 10))
    #expect(toBeCloseTo(try #require(convert(16, from: .tbsp, to: .cup)), 1, digits: 10))
    #expect(toBeCloseTo(try #require(convert(4, from: .cup, to: .quart)), 1, digits: 10))
    #expect(toBeCloseTo(try #require(convert(1, from: .gallon, to: .l)), 3.785, digits: 3))
    #expect(toBeCloseTo(try #require(convert(8, from: .flOz, to: .cup)), 1, digits: 10))
    #expect(toBeCloseTo(try #require(convert(2, from: .pint, to: .quart)), 1, digits: 10))
    #expect(convert(1, from: .l, to: .ml) == 1000)
  }

  @Test func convertsMass() throws {
    #expect(toBeCloseTo(try #require(convert(1, from: .lb, to: .g)), 453.592, digits: 2))
    #expect(toBeCloseTo(try #require(convert(16, from: .oz, to: .lb)), 1, digits: 10))
    #expect(convert(1.5, from: .kg, to: .g) == 1500)
  }

  @Test func isNilAcrossDimensionsAndBetweenDifferentCounts() {
    #expect(convert(1, from: .cup, to: .g) == nil)
    #expect(convert(1, from: .oz, to: .flOz) == nil)
    #expect(convert(1, from: .clove, to: .piece) == nil)
    #expect(convert(3, from: .clove, to: .clove) == 3)
  }

  @Test func roundTrips() throws {
    for a in UnitCode.allCases {
      for b in UnitCode.allCases {
        if let there = convert(7, from: a, to: b) {
          #expect(toBeCloseTo(try #require(convert(there, from: b, to: a)), 7, digits: 8))
        }
      }
    }
  }
}

struct UnitDisplayCase: Sendable {
  let quantity: Double
  let from: UnitCode
  let system: TargetSystem
  let expected: Double
  let unit: UnitCode
}

@Suite("convertForDisplay")
struct ConvertForDisplayTests {
  static let cases: [UnitDisplayCase] = [
    .init(quantity: 1, from: .cup, system: .metric, expected: 236.588, unit: .ml),
    .init(quantity: 4.5, from: .cup, system: .metric, expected: 1.0647, unit: .l),
    .init(quantity: 1, from: .tsp, system: .metric, expected: 4.929, unit: .ml),
    .init(quantity: 2, from: .lb, system: .metric, expected: 907.185, unit: .g),
    .init(quantity: 5, from: .lb, system: .metric, expected: 2.268, unit: .kg),
    .init(quantity: 8, from: .oz, system: .metric, expected: 226.796, unit: .g),
    .init(quantity: 250, from: .ml, system: .us, expected: 1.0567, unit: .cup),
    .init(quantity: 5, from: .ml, system: .us, expected: 1.0144, unit: .tsp),
    .init(quantity: 20, from: .ml, system: .us, expected: 1.352, unit: .tbsp),
    .init(quantity: 1000, from: .ml, system: .us, expected: 1.0567, unit: .quart),
    .init(quantity: 4, from: .l, system: .us, expected: 1.0567, unit: .gallon),
    .init(quantity: 100, from: .g, system: .us, expected: 3.527, unit: .oz),
    .init(quantity: 1, from: .kg, system: .us, expected: 2.2046, unit: .lb),
  ]

  @Test(arguments: cases)
  func convertsToTheSystem(_ c: UnitDisplayCase) {
    let out = convertForDisplay(c.quantity, unit: c.from, target: c.system)
    #expect(out.unit == c.unit)
    #expect(toBeCloseTo(out.quantity, c.expected, digits: 2))
  }

  @Test func stepsSmallUSVolumesDownWithinTheUSSystem() {
    #expect(convertForDisplay(0.125, unit: .cup, target: .us) == Measure(quantity: 2, unit: .tbsp))
    #expect(convertForDisplay(1.0 / 32, unit: .cup, target: .us).unit == .tsp)
    #expect(convertForDisplay(0.5, unit: .tbsp, target: .us) == Measure(quantity: 1.5, unit: .tsp))
    #expect(convertForDisplay(0.25, unit: .cup, target: .us) == Measure(quantity: 0.25, unit: .cup))
    #expect(convertForDisplay(1, unit: .tbsp, target: .us) == Measure(quantity: 1, unit: .tbsp))
  }

  @Test func leavesMatchingSystemsCountsPinchAndDashAlone() {
    #expect(convertForDisplay(2, unit: .cup, target: .us) == Measure(quantity: 2, unit: .cup))
    #expect(convertForDisplay(2, unit: .g, target: .metric) == Measure(quantity: 2, unit: .g))
    #expect(
      convertForDisplay(3, unit: .clove, target: .metric) == Measure(quantity: 3, unit: .clove))
    #expect(
      convertForDisplay(1, unit: .pinch, target: .metric) == Measure(quantity: 1, unit: .pinch))
    #expect(convertForDisplay(1, unit: .dash, target: .metric) == Measure(quantity: 1, unit: .dash))
  }
}

@Suite("Unit codes and parser output")
struct UnitSchemaTests {
  @Test func acceptsEveryUnitCodeAndRejectsOthers() {
    for code in UnitCode.allCases { #expect(UnitCode(rawValue: code.rawValue) == code) }
    #expect(UnitCode(rawValue: "furlong") == nil)
  }

  @Test func acceptsParserOutput() throws {
    let parsed = parseIngredientLine("1 1/2 cups (190g) flour, sifted")
    #expect(parsed.isValid)
    let decoded = try JSONDecoder().decode(
      ParsedIngredient.self, from: JSONEncoder().encode(parsed))
    #expect(decoded == parsed)
  }

  @Test func rejectsNegativeAndNonFiniteQuantities() {
    var bad = parseIngredientLine("1 cup milk")
    bad.quantity = Quantity(min: -1, max: nil)
    #expect(!bad.isValid)
    var infinite = parseIngredientLine("1 cup milk")
    infinite.quantity = Quantity(min: .infinity, max: nil)
    #expect(!infinite.isValid)
  }
}
