import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

// The expected numbers below come from the web: `buildCheckIn`, `isCheckInDue` and
// `trendForEstimate` in `apps/web/src/lib/check-in.ts`, run with bun over the history that
// `packages/db/src/seed-tracker.ts` generates for today = 2026-10-10 (the same seed
// `DebugSeed.populate` ports), with the seed's profile, its calculated targets and `checkedInOn`
// eight days before today. They are the web's answers for the same inputs; none are computed
// here.

@MainActor
@Suite("Weekly check-in")
struct CheckInTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!
  private let container: ModelContainer
  private let context: ModelContext

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
  }

  private func seeded() throws -> CheckInInputs {
    try DebugSeed.populate(context, today: today)
    return try CheckInInputs.gather(from: context, today: today)
  }

  private func near(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
  }

  // MARK: The same suggestion as the web

  @Test func fourWeeksOfSeededDataGiveTheWebsEstimate() throws {
    let check = try #require(try seeded().build(keepOverrides: true))
    let estimate = check.estimate
    #expect(estimate.loggedDays == 15 && estimate.weighIns == 16)
    #expect(estimate.windowDays == 21 && estimate.spanDays == 18)
    #expect(estimate.expenditure == 2370 && estimate.confidence == 1)
    #expect(near(estimate.measured, 2370.9114355231145, 1e-6))
    #expect(near(estimate.trendChangeKg, -1.5270656934306572, 1e-9))
    #expect(check.weeks == 3)
    #expect(near(check.weightKg, 73.15928239919572, 1e-9))
  }

  @Test func fourWeeksOfSeededDataGiveTheWebsProposal() throws {
    let proposal = try #require(try seeded().build(keepOverrides: true)).proposal
    #expect(proposal.targets == MacroTargets(calories: 1820, protein: 132, carbs: 210, fat: 51))
    #expect(!proposal.floored)
    #expect(proposal.dailyAdjustment == -550)
    #expect(proposal.expectedWeeklyChangeKg == -0.5)
    #expect(near(proposal.actualWeeklyChangeKg, -0.593858880778589, 1e-9))
  }

  @Test func handSetTargetsAreKeptOrCalculatedAgainAsTheWebDoes() throws {
    let inputs = try seeded()
    let row = try #require(try context.current(TargetsRecord.self))
    // Calories and fat typed in by hand.
    row.calories = 1800
    row.caloriesOverridden = true
    row.fat = 60
    row.fatOverridden = true
    try context.save()
    let changed = try CheckInInputs.gather(from: context, today: today)
    #expect(changed.hasHandSetTargets && !inputs.hasHandSetTargets)

    let kept = try #require(changed.build(keepOverrides: true)).proposal.targets
    #expect(kept == MacroTargets(calories: 1800, protein: 132, carbs: 206, fat: 60))
    let dropped = try #require(changed.build(keepOverrides: false)).proposal.targets
    #expect(dropped == MacroTargets(calories: 1820, protein: 132, carbs: 210, fat: 51))
  }

  @Test func tooLittleDataLeansOnTheCalculatorLikeTheWeb() throws {
    var inputs = try seeded()
    // Five days of weigh-ins and the last three days of food.
    inputs.weighIns = inputs.weighIns.filter { $0.date >= today.adding(days: -5) }
    inputs.intake = inputs.intake.filter { $0.date >= today.adding(days: -3) }
    let check = try #require(inputs.build(keepOverrides: true))
    let estimate = check.estimate
    #expect(estimate.measured == nil && estimate.confidence == 0)
    #expect(estimate.expenditure == 1970)
    #expect(estimate.loggedDays == 3 && estimate.weighIns == 5 && estimate.spanDays == 4)
    #expect(near(estimate.trendChangeKg, 0.07999999999998408, 1e-9))
    #expect(
      check.proposal.targets == MacroTargets(calories: 1420, protein: 131, carbs: 127, fat: 44))
    #expect(near(check.proposal.actualWeeklyChangeKg, 0.13999999999997215, 1e-9))
    #expect(near(check.weightKg, 72.52803999999999, 1e-9))
    #expect(!inputs.isDue)
  }

  @Test func theEstimateReadsTheStraightLineTrendUntilTheSmoothedOneHasWarmedUp() throws {
    let inputs = try seeded()
    let trend = CheckInRules.trendForEstimate(weighIns: inputs.weighIns, today: today)
    let last = Array(trend.suffix(3))
    #expect(last.map(\.date) == [7, 8, 9].map { LocalDate(year: 2026, month: 10, day: $0)! })
    #expect(near(last[0].trendKg, 72.66545498783454))
    #expect(near(last[1].trendKg, 72.58061800486617))
    #expect(near(last[2].trendKg, 72.4957810218978))
  }

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

  // MARK: Too little to go on

  @Test func withoutAWeighInThereIsNoCheckIn() throws {
    try DebugSeed.populate(context, today: today)
    for row in try context.fetch(FetchDescriptor<WeighInRecord>()) { context.delete(row) }
    try context.save()
    let inputs = try CheckInInputs.gather(from: context, today: today)
    #expect(inputs.build(keepOverrides: true) == nil)
    #expect(!inputs.isDue)
  }

  @Test func oneWeighInLeansEntirelyOnTheCalculator() throws {
    var inputs = try seeded()
    inputs.weighIns = [WeighIn(date: today, weightKg: 74)]
    let check = try #require(inputs.build(keepOverrides: true))
    #expect(check.estimate.measured == nil && check.estimate.confidence == 0)
    #expect(check.proposal.actualWeeklyChangeKg == nil)
    #expect(check.weightKg == 74)
  }

  @Test func withoutAProfileOrTargetsThereIsNothingToPropose() throws {
    var inputs = try seeded()
    inputs.profile = nil
    #expect(inputs.build(keepOverrides: true) == nil)
    inputs = try seeded()
    inputs.targets = nil
    #expect(inputs.build(keepOverrides: true) == nil)
  }

  @Test func aMealStillWaitingForItsNumbersIsNotADayOfNothing() throws {
    let before = try seeded().build(keepOverrides: true)?.estimate.loggedDays
    // A day inside the window with nothing logged, except a described meal still pending.
    let all = try context.fetch(FetchDescriptor<DiaryEntryRecord>())
    let logged = Set(all.map(\.dayKey))
    let empty = try #require(
      (0..<21).map { today.adding(days: -$0) }.first { !logged.contains($0.description) })
    let waiting = DiaryEntryRecord(day: empty, slot: .lunch, name: "Soup", source: .described)
    waiting.macrosPending = true
    context.insert(waiting)
    try context.save()
    let after = try CheckInInputs.gather(from: context, today: today).build(keepOverrides: true)
    #expect(after?.estimate.loggedDays == before)
  }

  @Test func weighInsAreOneADayByTheKeeperRule() throws {
    let inputs = try seeded()
    let dupe = WeighInRecord(day: today.adding(days: -1), weightKg: 99)
    dupe.updatedAt = Date(timeIntervalSince1970: 1)
    context.insert(dupe)
    try context.save()
    let again = try CheckInInputs.gather(from: context, today: today)
    #expect(again.weighIns == inputs.weighIns)
  }

  // MARK: When it is due

  @Test func aSeededStoreIsDue() throws {
    #expect(try seeded().isDue)
  }

  @Test func itIsDueOnceAWeekHasPassedSinceTheLastCheckIn() throws {
    let inputs = try seeded()
    func due(checkedIn days: Int?) -> Bool {
      var changed = inputs
      changed.targets?.checkedInOn = days.map { today.adding(days: -$0) }
      return changed.isDue
    }
    #expect(!due(checkedIn: 0) && !due(checkedIn: 6))
    #expect(due(checkedIn: 7) && due(checkedIn: 8))
    #expect(due(checkedIn: nil))
  }

  @Test func itNeedsAProfileTargetsAndAWeekOfWeighIns() {
    let profile = BodyProfile(
      sex: .female, birthDate: LocalDate(year: 1990, month: 5, day: 14)!, heightCm: 168,
      activity: .light, goal: .lose, weeklyRateKg: 0.5, proteinPerKg: 1.8, fatShare: 0.25,
      weightUnit: .kg, heightUnit: .cm)
    let targets = Targets(
      calories: 1450, protein: 134, carbs: 129, fat: 45,
      overridden: TargetOverrides(calories: false, protein: false, carbs: false, fat: false),
      checkedInOn: nil)
    func due(_ ago: [Int], profile: BodyProfile? = profile, targets: Targets? = targets) -> Bool {
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

  // MARK: Accepting and not now

  private func targetsRow() throws -> TargetsRecord {
    try #require(try context.current(TargetsRecord.self))
  }

  @Test func acceptingSetsTheTargetsAndChecksIn() throws {
    let check = try #require(try seeded().build(keepOverrides: true))
    try CheckInWrites.accept(check, keepOverrides: true, today: today, in: context)
    let row = try targetsRow()
    #expect([row.calories, row.protein, row.carbs, row.fat] == [1820, 132, 210, 51] as [Int])
    #expect(row.checkedInOn == today)
    #expect(!row.caloriesOverridden && !row.fatOverridden)
    // Not due again for a week.
    #expect(try !CheckInInputs.gather(from: context, today: today).isDue)
    #expect(try CheckInInputs.gather(from: context, today: today.adding(days: 7)).isDue)
  }

  @Test func acceptingKeepsHandSetTargetsWhenAskedTo() throws {
    try DebugSeed.populate(context, today: today)
    let row = try targetsRow()
    row.calories = 1800
    row.caloriesOverridden = true
    row.fat = 60
    row.fatOverridden = true
    try context.save()
    let inputs = try CheckInInputs.gather(from: context, today: today)
    let check = try #require(inputs.build(keepOverrides: true))
    try CheckInWrites.accept(check, keepOverrides: true, today: today, in: context)
    #expect([row.calories, row.protein, row.carbs, row.fat] == [1800, 132, 206, 60] as [Int])
    #expect(row.caloriesOverridden && row.fatOverridden && !row.proteinOverridden)
    #expect(row.checkedInOn == today)
  }

  @Test func acceptingWithoutKeepingCalculatesEverythingAgain() throws {
    try DebugSeed.populate(context, today: today)
    let row = try targetsRow()
    row.calories = 1800
    row.caloriesOverridden = true
    row.fat = 60
    row.fatOverridden = true
    try context.save()
    let inputs = try CheckInInputs.gather(from: context, today: today)
    let check = try #require(inputs.build(keepOverrides: false))
    try CheckInWrites.accept(check, keepOverrides: false, today: today, in: context)
    #expect([row.calories, row.protein, row.carbs, row.fat] == [1820, 132, 210, 51] as [Int])
    #expect(!row.caloriesOverridden && !row.fatOverridden)
    #expect(row.checkedInOn == today)
  }

  @Test func notNowChangesNothingButTheCheckInDay() throws {
    try DebugSeed.populate(context, today: today)
    let before = try targetsRow().targets
    try CheckInWrites.dismiss(today: today, in: context)
    var after = try targetsRow().targets
    #expect(after.checkedInOn == today)
    after.checkedInOn = before.checkedInOn
    #expect(after == before)
    #expect(try !CheckInInputs.gather(from: context, today: today).isDue)
  }

  @Test func theKeeperRowIsTheOneThatChanges() throws {
    try DebugSeed.populate(context, today: today)
    let older = try targetsRow()
    older.updatedAt = Date(timeIntervalSince1970: 1000)
    let newer = TargetsRecord(calories: 1500, protein: 100, carbs: 150, fat: 50)
    newer.updatedAt = Date(timeIntervalSince1970: 2000)
    context.insert(newer)
    try context.save()
    try CheckInWrites.dismiss(today: today, in: context)
    #expect(newer.checkedInOn == today)
    #expect(older.checkedInOn != today)
  }

  @Test func withoutTargetsThereIsNothingToChange() throws {
    #expect(throws: CheckInWrites.Failure.noTargets) {
      try CheckInWrites.dismiss(today: today, in: context)
    }
  }

  @Test func theProposalIsRecognisedAsUnchanged() throws {
    let inputs = try seeded()
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

  // MARK: Screens

  @Test func theCheckInDrawsInBothAppearances() throws {
    try DebugSeed.populate(context, today: today)
    for scheme in [ColorScheme.light, .dark] {
      let view = CheckInView(context: context, today: today).environment(\.colorScheme, scheme)
      #expect(ImageRenderer(content: view.frame(width: 390, height: 800)).cgImage != nil)
    }
  }

  @Test func theCheckInDrawsWithTooLittleData() throws {
    #expect(
      ImageRenderer(
        content: CheckInView(context: context, today: today).frame(width: 390, height: 800)
      ).cgImage != nil)
  }
}
