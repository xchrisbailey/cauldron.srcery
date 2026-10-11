import CauldronKit
import Foundation
import Testing

/// Ported case for case from `packages/shared/test/weight.test.ts`.
private func day(_ string: String) -> LocalDate { LocalDate(string)! }

private func w(_ date: String, _ weightKg: Double) -> WeighIn {
  WeighIn(date: day(date), weightKg: weightKg)
}

private func close(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
  abs(a - b) <= tolerance
}

@Suite("weight units")
struct WeightUnitTests {
  @Test func roundTripsKgAndLb() {
    #expect(close(toKg(1, unit: .lb), kgPerLb, within: 5e-11))
    #expect(toKg(80, unit: .kg) == 80)
    #expect(close(fromKg(toKg(180, unit: .lb), unit: .lb), 180, within: 5e-11))
    #expect(roundWeight(fromKg(80, unit: .lb)) == 176.4)
  }

  @Test func roundsToOneDecimal() {
    #expect(roundWeight(72.449) == 72.4)
    #expect(roundWeight(72.46) == 72.5)
  }

  @Test func convertsCmToFeetAndInches() {
    #expect(cmToFeetInches(180) == FeetInches(feet: 5, inches: 10.9))
    #expect(cmToFeetInches(152.4) == FeetInches(feet: 5, inches: 0))
  }

  @Test func carries1199InchesIntoTheNextFoot() {
    #expect(
      cmToFeetInches(feetInchesToCm(feet: 5, inches: 11.99)) == FeetInches(feet: 6, inches: 0))
  }

  @Test func roundTripsFtInThroughCm() {
    #expect(close(feetInchesToCm(feet: 5, inches: 10), 177.8, within: 5e-11))
    #expect(cmToFeetInches(feetInchesToCm(feet: 5, inches: 10)) == FeetInches(feet: 5, inches: 10))
  }
}

@Suite("trendSeries")
struct TrendSeriesTests {
  @Test func isEmptyForNoWeighIns() {
    #expect(trendSeries([]).isEmpty)
  }

  @Test func startsAtTheFirstWeight() {
    #expect(
      trendSeries([w("2026-10-01", 80)])
        == [TrendPoint(date: day("2026-10-01"), weightKg: 80, trendKg: 80)])
  }

  @Test func convergesTowardASteadyWeight() {
    let weighIns =
      [w("2026-01-01", 90)]
      + (0..<60).map { w(day("2026-01-02").adding(days: $0).description, 80) }
    let last = trendSeries(weighIns).last!
    #expect(last.trendKg > 80)
    #expect(last.trendKg < 80.5)
  }

  @Test func movesASingleSpikeByOnlyAlphaTimesTheSpike() {
    let series = trendSeries([w("2026-10-01", 80), w("2026-10-02", 80), w("2026-10-03", 85)])
    #expect(close(series[2].trendKg, 80 + trendSmoothing * 5, within: 5e-11))
  }

  @Test func scalesTheStepByTheGap() {
    let series = trendSeries([w("2026-10-01", 80), w("2026-10-06", 85)])
    #expect(close(series[1].trendKg, 80 + (1 - pow(0.9, 5)) * 5, within: 5e-11))
  }

  @Test func keepsTheLastWeighInForADuplicateDay() {
    let series = trendSeries([w("2026-10-01", 80), w("2026-10-01", 82)])
    #expect(series == [TrendPoint(date: day("2026-10-01"), weightKg: 82, trendKg: 82)])
  }

  @Test func sortsUnsortedInput() {
    let sorted = trendSeries([w("2026-10-01", 80), w("2026-10-02", 81), w("2026-10-04", 79)])
    let shuffled = trendSeries([w("2026-10-04", 79), w("2026-10-01", 80), w("2026-10-02", 81)])
    #expect(shuffled == sorted)
    #expect(shuffled.map(\.date) == [day("2026-10-01"), day("2026-10-02"), day("2026-10-04")])
  }
}

@Suite("trendOn and trendChange")
struct TrendOnTests {
  let series = trendSeries([w("2026-10-01", 80), w("2026-10-02", 81), w("2026-10-10", 79)])

  @Test func usesTheLastPointAtOrBeforeTheDay() {
    #expect(trendOn(series, date: day("2026-09-30")) == nil)
    #expect(trendOn(series, date: day("2026-10-01")) == 80)
    #expect(trendOn(series, date: day("2026-10-05")) == series[1].trendKg)
    #expect(trendOn(series, date: day("2026-12-01")) == series[2].trendKg)
  }

  @Test func reportsTheChangeOverASpan() {
    let change = trendChange(series, days: 9, today: day("2026-10-10"))!
    #expect(close(change, series[2].trendKg - 80, within: 5e-11))
  }

  @Test func isNilWhenEitherEndIsMissing() {
    #expect(trendChange(series, days: 30, today: day("2026-10-10")) == nil)
    #expect(trendChange(series, days: 7, today: day("2026-09-20")) == nil)
    #expect(trendChange([], days: 7, today: day("2026-10-10")) == nil)
  }
}

@Suite("rangeStart")
struct RangeStartTests {
  @Test func countsBackFromToday() {
    #expect(rangeStart(.oneMonth, today: day("2026-10-31")) == day("2026-10-01"))
    #expect(rangeStart(.threeMonths, today: day("2026-10-31")) == day("2026-08-01"))
    #expect(rangeStart(.oneYear, today: day("2026-10-31")) == day("2025-10-31"))
    #expect(rangeStart(.all, today: day("2026-10-31")) == nil)
  }
}
