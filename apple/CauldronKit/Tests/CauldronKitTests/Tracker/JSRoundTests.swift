import Testing

@testable import CauldronKit

/// `Math.round` rounds halves toward positive infinity, where Swift's `.rounded()` rounds them
/// away from zero. The expected values come from running the reference under Bun.
@Suite("JavaScript rounding")
struct JSRoundTests {
  struct Case: Sendable {
    let input: Double
    let expected: Double
  }

  static let cases: [Case] = [
    .init(input: 0.5, expected: 1),
    .init(input: 1.5, expected: 2),
    .init(input: 2.5, expected: 3),
    .init(input: -0.5, expected: 0),
    .init(input: -1.5, expected: -1),
    .init(input: -2.5, expected: -2),
    .init(input: -0.4, expected: 0),
    .init(input: 0.49999999999999994, expected: 0),
    .init(input: -0.5000000000000001, expected: -1),
    .init(input: 1234.4999, expected: 1234),
    .init(input: 4_503_599_627_370_497, expected: 4_503_599_627_370_497),
    .init(input: -4_503_599_627_370_497, expected: -4_503_599_627_370_497),
  ]

  @Test("matches Math.round", arguments: cases)
  func matchesMathRound(_ c: Case) {
    #expect(jsRound(c.input) == c.expected)
  }

  @Test func leavesNonFiniteValuesAlone() {
    #expect(jsRound(.infinity) == .infinity)
    #expect(jsRound(-.infinity) == -.infinity)
    #expect(jsRound(.nan).isNaN)
  }
}
