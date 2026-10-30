import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

// The rules and the maths are tested in CauldronKit (`CheckInTests`), with the web's numbers.
// These check what the app adds: that the seeded store gathers into the same inputs (the same
// numbers come out), and the writes and screens. The numbers are the web's, as pinned there.

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

  // MARK: Too little to go on

  @Test func withoutAWeighInThereIsNoCheckIn() throws {
    try DebugSeed.populate(context, today: today)
    for row in try context.fetch(FetchDescriptor<WeighInRecord>()) { context.delete(row) }
    try context.save()
    let inputs = try CheckInInputs.gather(from: context, today: today)
    #expect(inputs.build(keepOverrides: true) == nil)
    #expect(!inputs.isDue)
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

  // MARK: What counts

  @Test func aWeighInDatedAfterTodayChangesNothing() throws {
    let before = try seeded().build(keepOverrides: true)
    // From a device in a zone that is already tomorrow.
    context.insert(WeighInRecord(day: today.adding(days: 1), weightKg: 60))
    try context.save()
    let inputs = try CheckInInputs.gather(from: context, today: today)
    #expect(inputs.build(keepOverrides: true) == before)
    #expect(inputs.weighIns.allSatisfy { $0.date <= today })
  }

  @Test func aDayWithAMealStillWaitingIsNotLoggedYet() throws {
    let before = try #require(try seeded().build(keepOverrides: true))
    // A fully logged day in the window gets one more meal that is waiting for its numbers.
    let all = try context.fetch(FetchDescriptor<DiaryEntryRecord>())
    let from = CheckInRules.from(today: today).description
    let logged = try #require(
      all.map(\.dayKey).filter { $0 >= from && $0 <= today.description }.first)
    let waiting = DiaryEntryRecord(
      day: try #require(LocalDate(logged)), slot: .snack, name: "Soup", source: .described)
    waiting.macrosPending = true
    context.insert(waiting)
    try context.save()
    let after = try #require(
      try CheckInInputs.gather(from: context, today: today).build(keepOverrides: true))
    // The whole day leaves the average, not just the meal.
    #expect(after.estimate.loggedDays == before.estimate.loggedDays - 1)
    #expect(
      try CheckInInputs.gather(from: context, today: today).intake.allSatisfy {
        $0.date.description != logged
      })
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

  @Test func theCheckInStampsTheDayItIsAcceptedOn() throws {
    // Left open past midnight, the diary's idea of today is stale; the check-in is stamped with
    // the day it is given, which it reads from the clock when it opens.
    try DebugSeed.populate(context, today: today)
    let tomorrow = today.adding(days: 1)
    try CheckInWrites.dismiss(today: tomorrow, in: context)
    #expect(try targetsRow().checkedInOn == tomorrow)
  }
}

@Suite("Day rollover")
struct DayRolloverTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    return calendar
  }()

  private func at(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 10) -> Date {
    calendar.date(
      from: DateComponents(
        year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))
      ?? .now
  }

  @Test func theWaitIsToTheNextMidnightOnTheWallClock() {
    #expect(DayRollover.secondsUntilMidnight(now: at(23, 59, 30), calendar: calendar) == 30)
    #expect(DayRollover.secondsUntilMidnight(now: at(12, 0), calendar: calendar) == 12 * 3600)
    // At midnight itself the next one is a day off.
    #expect(DayRollover.secondsUntilMidnight(now: at(0, 0), calendar: calendar) == 86_400)
  }

  @Test func aDayWithAClockChangeIsStillMeasuredToMidnight() {
    // Clocks went back on 2026-11-01 in New York: 25 hours from midnight to midnight.
    let start = at(0, 0, day: 1)
    var november = DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 0)
    november.timeZone = calendar.timeZone
    let midnight = calendar.date(from: november) ?? start
    #expect(DayRollover.secondsUntilMidnight(now: midnight, calendar: calendar) == 25 * 3600)
  }

  @Test func todayFollowsTheClockPastMidnight() {
    let before = TargetsForm.today(now: at(23, 59, 59), calendar: calendar)
    let after = TargetsForm.today(now: at(0, 0, 1, day: 11), calendar: calendar)
    #expect(before == LocalDate(year: 2026, month: 10, day: 10))
    #expect(after == LocalDate(year: 2026, month: 10, day: 11))
  }

  @Test func targetsAndWeekUseGregorianDaysUnderNonGregorianCalendars() throws {
    let zone = try #require(TimeZone(identifier: "Pacific/Auckland"))
    let civil = DayKeyCalendar.make(timeZone: zone)
    for identifier in [Calendar.Identifier.buddhist, .japanese] {
      var calendar = Calendar(identifier: identifier)
      calendar.timeZone = zone
      let before = try #require(
        civil.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23, minute: 59)))
      let after = try #require(civil.date(from: DateComponents(year: 2026, month: 10, day: 11)))
      for (now, day) in [(before, LocalDate("2026-10-10")), (after, LocalDate("2026-10-11"))] {
        #expect(TargetsForm.today(now: now, calendar: calendar) == day)
        #expect(RecipeCooking.today(now: now, calendar: calendar) == day)
        #expect(WeekDates.today(now: now, calendar: calendar) == day)
      }
    }
  }
}
