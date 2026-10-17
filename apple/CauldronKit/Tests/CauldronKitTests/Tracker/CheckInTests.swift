import CauldronKit
import Foundation
import Testing

// The expected numbers come from the web: `buildCheckIn`, `isCheckInDue` and `trendForEstimate`
// in `apps/web/src/lib/check-in.ts`, run with bun over the history that
// `packages/db/src/seed-tracker.ts` generates for today = 2026-10-10 (the fixture below is that
// history, as the script printed it), with the seed's profile, its calculated targets and
// `checkedInOn` eight days before today. None are computed here.

private func day(_ string: String) -> LocalDate { LocalDate(string)! }

private let today = day("2026-10-10")

private func close(_ a: Double?, _ b: Double, within tolerance: Double = 1e-9) -> Bool {
  guard let a else { return false }
  return abs(a - b) <= tolerance
}

private let seedWeighIns: [WeighIn] = [
  ("2026-09-12", 74.35), ("2026-09-13", 74.07), ("2026-09-14", 73.61), ("2026-09-15", 74.53),
  ("2026-09-16", 74.19), ("2026-09-18", 73.96), ("2026-09-19", 73.98), ("2026-09-21", 73.81),
  ("2026-09-22", 73.9), ("2026-09-23", 73.86), ("2026-09-25", 73.88), ("2026-09-26", 73.54),
  ("2026-09-28", 73.55), ("2026-09-29", 73.35), ("2026-09-30", 73.34), ("2026-10-01", 73.47),
  ("2026-10-02", 73.02), ("2026-10-04", 72.95), ("2026-10-05", 72.48), ("2026-10-06", 72.68),
  ("2026-10-07", 72.34), ("2026-10-08", 73.1), ("2026-10-09", 72.37),
].map { WeighIn(date: day($0.0), weightKg: $0.1) }

/// Days with food logged: the date, the entries, and the day's calories.
private let seedIntake: [IntakeDay] = [
  ("2026-09-13", 5, 1553.0), ("2026-09-15", 5, 2020), ("2026-09-17", 5, 1993),
  ("2026-09-18", 5, 1888), ("2026-09-19", 5, 1583), ("2026-09-20", 5, 1193),
  ("2026-09-22", 5, 1540), ("2026-09-23", 3, 1520), ("2026-09-26", 4, 1345),
  ("2026-09-28", 5, 1823), ("2026-09-29", 6, 2038), ("2026-09-30", 5, 1480),
  ("2026-10-01", 5, 2125), ("2026-10-03", 6, 1973), ("2026-10-04", 3, 1970),
  ("2026-10-05", 6, 1870), ("2026-10-06", 6, 1570), ("2026-10-07", 4, 1370),
  ("2026-10-08", 4, 2065), ("2026-10-09", 6, 1883),
].map {
  IntakeDay(
    date: day($0.0), entries: $0.1,
    totals: MacroTotals(calories: $0.2, protein: 0, carbs: 0, fat: 0))
}

private let seedProfile = BodyProfile(
  sex: .female, birthDate: day("1990-05-14"), heightCm: 168, activity: .light, goal: .lose,
  weeklyRateKg: 0.5, proteinPerKg: 1.8, fatShare: 0.25, weightUnit: .kg, heightUnit: .cm)

private func seedTargets(
  calories: Int = 1450, fat: Int = 45, overridden: TargetOverrides = .none,
  checkedInOn: LocalDate? = today.adding(days: -8)
) -> Targets {
  Targets(
    calories: calories, protein: 134, carbs: 129, fat: fat, overridden: overridden,
    checkedInOn: checkedInOn)
}

extension TargetOverrides {
  fileprivate static let none = TargetOverrides(
    calories: false, protein: false, carbs: false, fat: false)
}

private func seeded(targets: Targets = seedTargets()) -> CheckInInputs {
  CheckInInputs(
    profile: seedProfile, targets: targets, weighIns: seedWeighIns, intake: seedIntake,
    today: today)
}

@Suite("Weekly check-in")
struct CheckInTests {
  // MARK: The web's numbers

  @Test func fourWeeksOfSeededDataGiveTheWebsEstimate() throws {
    let check = try #require(seeded().build(keepOverrides: true))
    let estimate = check.estimate
    #expect(estimate.loggedDays == 15 && estimate.weighIns == 16)
    #expect(estimate.windowDays == 21 && estimate.spanDays == 18)
    #expect(estimate.expenditure == 2370 && estimate.confidence == 1)
    #expect(close(estimate.measured, 2370.9114355231145, within: 1e-6))
    #expect(close(estimate.trendChangeKg, -1.5270656934306572))
    #expect(check.weeks == 3)
    #expect(close(check.weightKg, 73.15928239919572))
  }

  @Test func fourWeeksOfSeededDataGiveTheWebsProposal() throws {
    let proposal = try #require(seeded().build(keepOverrides: true)).proposal
    #expect(proposal.targets == MacroTargets(calories: 1820, protein: 132, carbs: 210, fat: 51))
    #expect(!proposal.floored)
    #expect(proposal.dailyAdjustment == -550)
    #expect(proposal.expectedWeeklyChangeKg == -0.5)
    #expect(close(proposal.actualWeeklyChangeKg, -0.593858880778589))
  }

  @Test func handSetTargetsAreKeptOrCalculatedAgainAsTheWebDoes() throws {
    let hand = seeded(
      targets: seedTargets(
        calories: 1800, fat: 60,
        overridden: TargetOverrides(calories: true, protein: false, carbs: false, fat: true)))
    #expect(hand.hasHandSetTargets && !seeded().hasHandSetTargets)
    let kept = try #require(hand.build(keepOverrides: true)).proposal.targets
    #expect(kept == MacroTargets(calories: 1800, protein: 132, carbs: 206, fat: 60))
    let dropped = try #require(hand.build(keepOverrides: false)).proposal.targets
    #expect(dropped == MacroTargets(calories: 1820, protein: 132, carbs: 210, fat: 51))
  }

  @Test func tooLittleDataLeansOnTheCalculatorLikeTheWeb() throws {
    var inputs = seeded()
    inputs.weighIns = seedWeighIns.filter { $0.date >= today.adding(days: -5) }
    inputs.intake = seedIntake.filter { $0.date >= today.adding(days: -3) }
    let check = try #require(inputs.build(keepOverrides: true))
    #expect(check.estimate.measured == nil && check.estimate.confidence == 0)
    #expect(check.estimate.expenditure == 1970)
    #expect(check.estimate.loggedDays == 3 && check.estimate.weighIns == 5)
    #expect(check.estimate.spanDays == 4)
    #expect(close(check.estimate.trendChangeKg, 0.07999999999998408))
    #expect(
      check.proposal.targets == MacroTargets(calories: 1420, protein: 131, carbs: 127, fat: 44))
    #expect(close(check.proposal.actualWeeklyChangeKg, 0.13999999999997215))
    #expect(close(check.weightKg, 72.52803999999999))
    #expect(!inputs.isDue)
  }

  @Test func theEstimateReadsTheStraightLineTrendUntilTheSmoothedOneHasWarmedUp() {
    let trend = CheckInRules.trendForEstimate(weighIns: seedWeighIns, today: today)
    let last = Array(trend.suffix(3))
    #expect(last.map(\.date) == [day("2026-10-07"), day("2026-10-08"), day("2026-10-09")])
    #expect(close(last[0].trendKg, 72.66545498783454))
    #expect(close(last[1].trendKg, 72.58061800486617))
    #expect(close(last[2].trendKg, 72.4957810218978))
  }

  // MARK: The trend the estimate reads

  @Test func anOldEnoughHistoryUsesTheSmoothedTrend() {
    // The first weigh-in is more than two weeks before the window starts.
    let weighIns = [-40, -30, -20, -10, -1].map {
      WeighIn(date: today.adding(days: $0), weightKg: 80 - Double($0) / 10)
    }
    let trend = CheckInRules.trendForEstimate(weighIns: weighIns, today: today)
    #expect(trend.map(\.trendKg) == trendSeries(weighIns).map(\.trendKg))
    #expect(trend.count == 5)
  }

  @Test func aSingleWeighInInTheWindowIsUsedAsIs() {
    let weighIns = [WeighIn(date: today.adding(days: -2), weightKg: 71.5)]
    #expect(
      CheckInRules.trendForEstimate(weighIns: weighIns, today: today)
        == [TrendDay(date: today.adding(days: -2), trendKg: 71.5)])
  }

  @Test func noWeighInsMeansNoTrend() {
    #expect(CheckInRules.trendForEstimate(weighIns: [], today: today).isEmpty)
  }

  // MARK: Too little to go on

  @Test func withoutAWeighInThereIsNoCheckIn() {
    var inputs = seeded()
    inputs.weighIns = []
    #expect(inputs.build(keepOverrides: true) == nil)
    #expect(!inputs.isDue)
  }

  @Test func oneWeighInLeansEntirelyOnTheCalculator() throws {
    var inputs = seeded()
    inputs.weighIns = [WeighIn(date: today, weightKg: 74)]
    let check = try #require(inputs.build(keepOverrides: true))
    #expect(check.estimate.measured == nil && check.estimate.confidence == 0)
    #expect(check.proposal.actualWeeklyChangeKg == nil)
    #expect(check.weightKg == 74)
  }

  @Test func withoutAProfileOrTargetsThereIsNothingToPropose() {
    var inputs = seeded()
    inputs.profile = nil
    #expect(inputs.build(keepOverrides: true) == nil)
    inputs = seeded()
    inputs.targets = nil
    #expect(inputs.build(keepOverrides: true) == nil)
  }

  // MARK: When it is due

  @Test func aSeededStoreIsDue() {
    #expect(seeded().isDue)
  }

  @Test func itIsDueOnceAWeekHasPassedSinceTheLastCheckIn() {
    func due(checkedIn days: Int?) -> Bool {
      seeded(targets: seedTargets(checkedInOn: days.map { today.adding(days: -$0) })).isDue
    }
    #expect(!due(checkedIn: 0) && !due(checkedIn: 6))
    #expect(due(checkedIn: 7) && due(checkedIn: 8))
    #expect(due(checkedIn: nil))
  }

  @Test func itNeedsAProfileTargetsAndAWeekOfWeighIns() {
    func due(_ ago: [Int], profile: BodyProfile? = seedProfile, targets: Targets? = seedTargets())
      -> Bool
    {
      CheckInRules.isDue(
        profile: profile, targets: targets, weighInDays: ago.map { today.adding(days: -$0) },
        today: today)
    }
    #expect(due([8, 1]))
    #expect(!due([8, 1], profile: nil))
    #expect(!due([8, 1], targets: nil))
    // Two weigh-ins, but less than a week apart, or only one.
    #expect(!due([6, 0]) && due([7, 0]) && !due([3]) && !due([]))
    // A pair that is a week apart but older than the window doesn't count.
    #expect(!due([30, 23]))
    // Weigh-ins after today aren't looked at either.
    #expect(!due([0, -7]))
  }

  @Test func theWindowStartsTwentyDaysBack() {
    #expect(CheckInRules.from(today: today) == day("2026-09-20"))
    #expect(CheckInRules.hasWeekOfData([day("2026-10-01"), day("2026-10-08")]))
    #expect(!CheckInRules.hasWeekOfData([day("2026-10-01"), day("2026-10-07")]))
  }

  @Test func theProposalIsRecognisedAsUnchanged() throws {
    let inputs = seeded()
    let check = try #require(inputs.build(keepOverrides: true))
    let targets = try #require(inputs.targets)
    #expect(!check.isUnchanged(from: targets))
    var same = targets
    same.calories = check.proposal.targets.calories
    same.protein = check.proposal.targets.protein
    same.carbs = check.proposal.targets.carbs
    same.fat = check.proposal.targets.fat
    #expect(check.isUnchanged(from: same))
  }
}
