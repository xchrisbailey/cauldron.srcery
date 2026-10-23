import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

@Suite("Weight text")
struct WeightTextTests {
  @Test func typedWeightsBecomeKilograms() {
    #expect(WeightText.parse("74.2", unit: .kg) == 74.2)
    #expect(WeightText.parse(" 74,2 ", unit: .kg) == 74.2)
    #expect(WeightText.parse("165", unit: .lb) == toKg(165, unit: .lb))
    // Rounded to one decimal in the unit it was typed in, as the scale does.
    #expect(WeightText.parse("74.26", unit: .kg) == 74.3)
  }

  @Test func weightsThatCouldNotBeOnAScaleAreRefused() {
    for text in ["", "abc", "0", "-5", "19.9", "400.1", "nan", "inf"] {
      #expect(WeightText.parse(text, unit: .kg) == nil, "\(text)")
    }
    #expect(WeightText.parse("20", unit: .kg) == 20)
    #expect(WeightText.parse("400", unit: .kg) == 400)
    #expect(WeightText.parse("44", unit: .lb) == nil)
    #expect(WeightText.parse("44.1", unit: .lb) != nil)
  }

  @Test func limitsAreRoundedSoBothEndsAreValid() {
    let kg = WeightText.limits(unit: .kg)
    #expect(kg.min == 20 && kg.max == 400)
    let lb = WeightText.limits(unit: .lb)
    #expect(lb.min == 44.1 && lb.max == 881.8)
  }

  @Test func weightsAreShownWithOneDecimal() {
    #expect(WeightText.label(kg: 73, unit: .kg) == "73.0")
    #expect(WeightText.label(kg: 74.25, unit: .kg) == "74.3")
    #expect(WeightText.label(kg: 74.8, unit: .lb) == "164.9")
  }

  @Test func changesCarryTheirSign() {
    #expect(WeightText.signedChange(deltaKg: 0.4, unit: .kg) == "+0.4")
    #expect(WeightText.signedChange(deltaKg: -1.24, unit: .kg) == "−1.2")
    #expect(WeightText.signedChange(deltaKg: 0.01, unit: .kg) == "0.0")
    #expect(WeightText.signedChange(deltaKg: -0.01, unit: .kg) == "0.0")
    #expect(WeightText.signedChange(deltaKg: 1, unit: .lb) == "+2.2")
  }

  @Test func tickValuesAreRoundNumbersCoveringTheRange() {
    #expect(WeightText.niceTicks(min: 71.2, max: 74.6) == [71, 72, 73, 74, 75])
    #expect(WeightText.niceTicks(min: 70, max: 90) == [70, 75, 80, 85, 90])
    #expect(WeightText.niceTicks(min: 72.4, max: 72.4) == [71, 72, 73])
    let ticks = WeightText.niceTicks(min: 163.2, max: 171.9)
    #expect((ticks.first ?? 999) <= 163.2 && (ticks.last ?? 0) >= 171.9)
  }
}

@MainActor
@Suite("Weight history")
struct WeightHistoryTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!
  private let container: ModelContainer
  private let context: ModelContext

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
  }

  private func weighIns(_ values: [(Int, Double)]) -> [WeighIn] {
    values.map { WeighIn(date: today.adding(days: $0.0), weightKg: $0.1) }
  }

  @Test func theTrendFollowsTheWebsSmoothing() {
    let history = WeightHistory(
      weighIns: weighIns([(-2, 74), (-1, 73), (0, 73)]), today: today)
    #expect(history.series.map(\.weightKg) == [74, 73, 73])
    #expect(history.series[0].trendKg == 74)
    // 74 + 0.1 * (73 - 74) after one day, then 73.9 + 0.1 * (73 - 73.9).
    #expect(abs(history.series[1].trendKg - 73.9) < 1e-9)
    #expect(abs(history.series[2].trendKg - 73.81) < 1e-9)
    #expect(history.trendNow == history.series[2].trendKg)
  }

  @Test func theWeekAndMonthChangesNeedAWeighInBeforeTheStart() {
    let history = WeightHistory(weighIns: weighIns([(-10, 76), (0, 74)]), today: today)
    #expect(history.weekChange != nil)
    #expect(history.monthChange == nil)
    #expect(WeightHistory(weighIns: [], today: today).trendNow == nil)
  }

  @Test func rangesCutTheSeriesAndAllStartsAtTheFirstWeighIn() {
    let history = WeightHistory(
      weighIns: weighIns([(-200, 80), (-80, 78), (-20, 76), (0, 75)]), today: today)
    #expect(history.visible(.oneMonth).count == 2)
    #expect(history.visible(.threeMonths).count == 3)
    #expect(history.visible(.oneYear).count == 4)
    #expect(history.visible(.all).count == 4)
    #expect(history.start(of: .all) == today.adding(days: -200))
    #expect(history.start(of: .oneMonth) == today.adding(days: -30))
    #expect(history.list(.threeMonths).map(\.date) == [0, -20, -80].map { today.adding(days: $0) })
  }

  @Test func oneWeighInADayWhateverTheRowsHold() {
    let older = WeighInRecord(day: today, weightKg: 75)
    older.updatedAt = Date(timeIntervalSince1970: 1000)
    let newer = WeighInRecord(day: today, weightKg: 74)
    newer.updatedAt = Date(timeIntervalSince1970: 2000)
    for row in [older, newer] { context.insert(row) }
    #expect(WeightHistory.weighIns(of: [older, newer]) == [WeighIn(date: today, weightKg: 74)])
  }

  @Test func theChartHasADotAndATrendPointForEachWeighIn() {
    let history = WeightHistory(weighIns: weighIns([(-2, 74), (0, 73)]), today: today)
    let data = WeightChartData(
      points: history.visible(.oneMonth), unit: .kg, start: history.start(of: .oneMonth),
      end: today)
    #expect(data.dots.map(\.value) == [74, 73])
    #expect(data.line.count == 2)
    #expect(data.yTicks == [73, 73.5, 74])
    #expect(data.yDomain == 73...74)
    #expect(data.start == today.adding(days: -30) && data.end == today)
  }

  @Test func theChartIsInTheCooksUnit() {
    let history = WeightHistory(weighIns: weighIns([(0, 74.8)]), today: today)
    let data = WeightChartData(points: history.series, unit: .lb, start: today, end: today)
    #expect(abs((data.dots.first?.value ?? 0) - 164.9) < 0.05)
  }

  @Test func anEmptyChartStillHasAxes() {
    let data = WeightChartData(points: [], unit: .kg, start: today, end: today)
    #expect(data.dots.isEmpty && data.yTicks == [0, 1])
  }

  // MARK: Intake

  @Test func averageIntakeCountsOnlyDaysWithFood() {
    let days = [
      IntakeDay(
        date: today, entries: 3,
        totals: MacroTotals(calories: 2000, protein: 100, carbs: 200, fat: 60)),
      IntakeDay(
        date: today.adding(days: -1), entries: 2,
        totals: MacroTotals(calories: 1000, protein: 60, carbs: 100, fat: 20)),
      IntakeDay(date: today.adding(days: -2), entries: 0, totals: .zero),
    ]
    let averages = IntakeAverages(days: days)
    #expect(averages?.days == 2)
    #expect(averages?.totals == MacroTotals(calories: 1500, protein: 80, carbs: 150, fat: 40))
    #expect(IntakeAverages(days: [days[2]]) == nil)
    #expect(IntakeAverages(days: []) == nil)
  }

  @Test func intakeDaysCombineTheEntriesOfEachDay() throws {
    let a = DiaryEntryRecord(day: today, slot: .lunch, name: "A", servings: 2, source: .manual)
    a.macros = Macros(calories: 100, protein: 10)
    let b = DiaryEntryRecord(day: today, slot: .dinner, name: "B", source: .manual)
    b.macros = Macros(calories: 300)
    let c = DiaryEntryRecord(
      day: today.adding(days: -1), slot: .lunch, name: "C", source: .manual)
    c.macros = Macros(calories: 50)
    for row in [a, b, c] { context.insert(row) }
    let days = IntakeAverages.days(of: [a, b, c])
    #expect(days.map(\.date) == [today.adding(days: -1), today])
    #expect(days.map(\.entries) == [1, 2])
    #expect(days[1].totals == MacroTotals(calories: 500, protein: 20, carbs: 0, fat: 0))
  }

  // MARK: Writes

  private func rows() throws -> [WeighInRecord] {
    try context.fetch(FetchDescriptor<WeighInRecord>()).sorted { $0.dayKey < $1.dayKey }
  }

  @Test func oneWeighInADayAndEditingTodaysUpdatesTheRow() throws {
    try WeightWrites.save(kg: 74.2, on: today, today: today, in: context)
    try WeightWrites.save(kg: 73.9, on: today, today: today, in: context)
    #expect(try rows().map(\.weightKg) == [73.9])
    try WeightWrites.save(kg: 75.123, on: today.adding(days: -3), today: today, in: context)
    #expect(try rows().map(\.dayKey) == ["2026-10-07", "2026-10-10"])
    #expect(try rows()[0].weightKg == 75.12)
  }

  @Test func aWeightTypedOverAHealthOneBecomesTheCooksOwn() throws {
    let imported = WeighInRecord(day: today, weightKg: 74)
    imported.healthSampleID = "s1"
    context.insert(imported)
    try WeightWrites.save(kg: 73.5, on: today, today: today, in: context)
    #expect(try rows().map(\.healthSampleID) == [nil])
  }

  @Test func theFutureAndImpossibleWeightsAreRefused() throws {
    for (kg, day) in [
      (74.0, today.adding(days: 1)), (19.9, today), (.nan, today), (.infinity, today),
    ] {
      #expect(throws: WeightWrites.Failure.invalid) {
        try WeightWrites.save(kg: kg, on: day, today: self.today, in: context)
      }
    }
    #expect(try rows().isEmpty)
  }

  @Test func removingGivesBackTheHealthSampleToRemember() throws {
    let imported = WeighInRecord(day: today, weightKg: 74)
    imported.healthSampleID = "s1"
    context.insert(imported)
    let typed = WeighInRecord(day: today.adding(days: -1), weightKg: 75)
    context.insert(typed)
    #expect(try WeightWrites.remove(day: today, in: context) == "s1")
    #expect(try WeightWrites.remove(day: today.adding(days: -1), in: context) == nil)
    #expect(try WeightWrites.remove(day: today, in: context) == nil)
    #expect(try rows().isEmpty)
  }
}

@MainActor
@Suite("Weight screens")
struct WeightViewsTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!

  private func draws(_ view: some View) -> Bool {
    ImageRenderer(content: view.frame(width: 390, height: 800)).cgImage != nil
  }

  @Test func theWeightScreenDrawsASeededYearInBothAppearances() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    try DebugSeed.populate(context, today: today)
    for scheme in [ColorScheme.light, .dark] {
      let view = WeightView(today: today)
        .environment(HealthSync.forLaunch(mode: .inMemory)).modelContainer(container)
        .environment(\.colorScheme, scheme)
      #expect(draws(view), "\(scheme)")
    }
  }

  @Test func theWeightScreenDrawsEmpty() throws {
    let container = try CauldronStore.container(.inMemory)
    let view = WeightView(today: today)
      .environment(HealthSync.forLaunch(mode: .inMemory)).modelContainer(container)
    #expect(draws(view))
  }

  @Test func theWeighInSheetDrawsNewAndExisting() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let row = WeighInRecord(day: today, weightKg: 74.2)
    context.insert(row)
    let fresh = WeightEntrySheet(
      day: today, today: today, unit: .lb, existing: nil, pickDay: true, onClose: {})
    let change = WeightEntrySheet(
      day: today, today: today, unit: .kg, existing: row, pickDay: false, onClose: {})
    #expect(draws(fresh.modelContainer(container)))
    #expect(draws(change.modelContainer(container)))
  }

  @Test func theHealthSectionDraws() throws {
    // Test renders use the no-access service even on a device with HealthKit enabled.
    let container = try CauldronStore.container(.inMemory)
    let view = Form { HealthKitSection() }
      .environment(HealthSync.forLaunch(mode: .inMemory))
      .modelContainer(container)
    #expect(draws(view))
    #expect(HealthSync.forLaunch(mode: .inMemory).status == .notSetUp)
  }
}
