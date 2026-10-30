import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing
import WidgetKit

@testable import Cauldron

/// A calendar and a clock that stay put, so a test knows which day it is.
private let utc: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
  return calendar
}()

private let today = LocalDate(year: 2026, month: 10, day: 10)!
private let noon = utc.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!

/// An empty folder of its own, removed when the test ends, so no test writes the real container.
private final class ScratchFolder {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appending(
      path: "today-macros-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: url) }

  var file: URL { url.appending(path: TodayMacrosFile.fileName) }
}

private func snapshot(
  day: LocalDate = today, calories: Double = 800, targets: MacroTargets? = nil,
  waiting: Bool = false
) -> TodayMacrosSnapshot {
  TodayMacrosSnapshot(
    day: day, eaten: MacroTotals(calories: calories, protein: 50, carbs: 90, fat: 20),
    targets: targets, hasWaitingEntry: waiting, writtenAt: noon)
}

private let targets = MacroTargets(calories: 2000, protein: 140, carbs: 220, fat: 65)

// MARK: The calculation

@MainActor
@Suite("Today's macros snapshot")
struct TodayMacrosSnapshotTests {
  private let container: ModelContainer
  private let context: ModelContext
  private let folder: ScratchFolder
  private let publisher: TodayMacrosPublisher

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
    folder = try ScratchFolder()
    publisher = TodayMacrosPublisher(folder: folder.url, now: { noon }, calendar: utc)
  }

  private func log(
    _ name: String, _ slot: MealSlot, calories: Double?, servings: Double = 1,
    on day: LocalDate = today, pending: Bool = false
  ) throws {
    try DiaryWrites.add(
      [
        NewEntry(
          name: name, servings: servings,
          macros: Macros(calories: calories, protein: calories.map { $0 / 20 }, carbs: 10, fat: 5),
          source: .manual, macrosPending: pending)
      ], on: day, slot: slot, in: context)
  }

  private func setTargets() {
    context.insert(TargetsRecord(calories: 2000, protein: 140, carbs: 220, fat: 65))
  }

  @Test func anEmptyDayIsZeroAgainstTheTargets() throws {
    setTargets()
    let result = try publisher.snapshot(from: context)
    #expect(result.day == today)
    #expect(result.eaten == .zero)
    #expect(result.targets == targets)
    #expect(!result.hasWaitingEntry)
    #expect(result.writtenAt == noon)
  }

  @Test func severalMealsAndServingsAddUpToTheDiaryHeadersTotals() throws {
    setTargets()
    try log("Oats", .breakfast, calories: 300)
    try log("Soup", .lunch, calories: 210, servings: 1.5)
    try log("Rice", .dinner, calories: 400, servings: 2)
    try log("Apple", .snack, calories: 95)
    try log("Mystery", .snack, calories: nil)

    let records = try context.fetch(
      FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.dayKey == "2026-10-10" }))
    let header = MacroMeter.meters(
      totals: DayLog(day: today, records: records).totals, targets: targets)
    let result = try publisher.snapshot(from: context)

    let expectedCalories: Double = 300 + 315 + 800 + 95
    #expect(result.eaten.calories == expectedCalories)
    for meter in header {
      #expect(result.eaten[meter.key] == meter.eaten, "\(meter.key)")
      #expect(result.meter(meter.key).eatenText == meter.eatenText, "\(meter.key)")
      #expect(result.meter(meter.key).target == meter.target, "\(meter.key)")
    }
  }

  @Test func noTargetsLeavesThemNil() throws {
    try log("Oats", .breakfast, calories: 300)
    let result = try publisher.snapshot(from: context)
    #expect(result.targets == nil)
    #expect(result.eaten.calories == 300)
    #expect(result.meter(.calories).target == nil && result.meter(.calories).fill == 0)
  }

  @Test func aWaitingEntryIsFlaggedAndCountsNothingYet() throws {
    setTargets()
    try log("Oats", .breakfast, calories: 300)
    try log("Two eggs and toast", .lunch, calories: nil, pending: true)
    let result = try publisher.snapshot(from: context)
    #expect(result.hasWaitingEntry)
    #expect(result.eaten.calories == 300)
  }

  @Test func yesterdaysEntriesAreLeftOut() throws {
    try log("Late supper", .dinner, calories: 700, on: today.adding(days: -1))
    try log("Waiting then", .dinner, calories: nil, on: today.adding(days: -1), pending: true)
    try log("Oats", .breakfast, calories: 300)
    try log("Tomorrow's", .breakfast, calories: 123, on: today.adding(days: 1))
    let result = try publisher.snapshot(from: context)
    #expect(result.eaten.calories == 300)
    #expect(!result.hasWaitingEntry)
  }

  @Test func theDayIsWorkedOutInTheCooksCalendar() throws {
    // 23:30 in New York is already the next day in UTC.
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    let lateEvening = newYork.date(
      from: DateComponents(year: 2026, month: 10, day: 10, hour: 23, minute: 30))!
    let publisher = TodayMacrosPublisher(
      folder: folder.url, now: { lateEvening }, calendar: newYork)
    try log("Oats", .breakfast, calories: 300)
    let result = try publisher.snapshot(from: context)
    #expect(result.day == today)
    #expect(result.eaten.calories == 300)
  }

  @Test func makeIgnoresEntriesOfOtherDaysEvenIfHandedThem() {
    let mine = DiaryEntry(
      id: UUID(), date: today, slot: .lunch, name: "A", amount: nil, servings: 2,
      macros: Macros(calories: 100, protein: 1, carbs: 2, fat: 3), source: .manual, recipeId: nil,
      position: 0)
    var other = mine
    other.date = today.adding(days: -1)
    let result = TodayMacrosSnapshot.make(
      day: today, entries: [mine, other], hasWaitingEntry: false, targets: nil, now: noon)
    #expect(result.eaten == MacroTotals(calories: 200, protein: 2, carbs: 4, fat: 6))
  }

  @Test func theMeterFillsToTheTargetAndStopsThere() {
    let under = snapshot(calories: 500, targets: targets).meter(.calories)
    #expect(under.fill == 0.25 && !under.isOver)
    let over = snapshot(calories: 2600, targets: targets).meter(.calories)
    #expect(over.fill == 1 && over.isOver)
    let zeroTarget = TodayMacrosMeter(key: .fat, eaten: 5, target: 0)
    #expect(zeroTarget.fill == 0)
    #expect(TodayMacrosMeter.whole(0.5) == "1" && TodayMacrosMeter.whole(0.4) == "0")
  }
}

// MARK: The file

@Suite("Today's macros file")
struct TodayMacrosFileTests {
  @Test func aSnapshotSurvivesTheRoundTrip() throws {
    let folder = try ScratchFolder()
    let written = snapshot(targets: targets, waiting: true)
    try TodayMacrosFile.write(written, to: folder.url)
    #expect(TodayMacrosFile.read(from: folder.url) == written)
  }

  @Test func theDayIsStoredAsPlainYearMonthDay() throws {
    let folder = try ScratchFolder()
    try TodayMacrosFile.write(snapshot(), to: folder.url)
    let text = try String(contentsOf: folder.file, encoding: .utf8)
    #expect(text.contains("\"day\":\"2026-10-10\""))
  }

  @Test func aNewSnapshotReplacesTheOldOne() throws {
    let folder = try ScratchFolder()
    try TodayMacrosFile.write(snapshot(calories: 100), to: folder.url)
    try TodayMacrosFile.write(snapshot(calories: 900), to: folder.url)
    #expect(TodayMacrosFile.read(from: folder.url)?.eaten.calories == 900)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.url.path())
    #expect(leftovers == [TodayMacrosFile.fileName])
  }

  @Test func aMissingFileReadsAsNothing() throws {
    let folder = try ScratchFolder()
    #expect(TodayMacrosFile.read(from: folder.url) == nil)
    #expect(TodayMacrosFile.read(from: nil) == nil)
  }

  @Test(
    "a file that can't be read reads as nothing",
    arguments: ["", "not json", "{}", #"{"day":"2026-02-30"}"#, #"{"day":"2026-10-10","eaten":1}"#])
  func anUnreadableFile(_ contents: String) throws {
    let folder = try ScratchFolder()
    try contents.write(to: folder.file, atomically: true, encoding: .utf8)
    #expect(TodayMacrosFile.read(from: folder.url) == nil)
  }

  @Test func writingWithNowhereToWriteFails() {
    #expect(throws: (any Error).self) { try TodayMacrosFile.write(snapshot(), to: nil) }
  }

  @Test func aSnapshotOfAnotherDayReadsAsTodayWithNothingEaten() {
    let yesterday = snapshot(
      day: today.adding(days: -1), calories: 1900, targets: targets, waiting: true)
    let seen = yesterday.seen(on: today)
    #expect(seen.day == today)
    #expect(seen.eaten == .zero)
    #expect(seen.targets == targets)
    #expect(!seen.hasWaitingEntry)
    // Today's own is as it was.
    let own = snapshot(calories: 1200, targets: targets)
    #expect(own.seen(on: today) == own)
  }
}

// MARK: The widget's timeline

@Suite("Today's macros timeline")
struct TodayMacrosTimelineTests {
  @Test func todayShowsTheSnapshotAndMidnightStartsAFreshDay() throws {
    let plan = TodayMacrosTimeline.plan(
      snapshot: snapshot(calories: 1200, targets: targets), now: noon, calendar: utc)
    let midnight = utc.date(from: DateComponents(year: 2026, month: 10, day: 11))!
    #expect(plan.entries.map(\.date) == [noon, midnight])
    #expect(plan.entries[0].snapshot?.eaten.calories == 1200)
    #expect(plan.entries[1].snapshot?.day == today.adding(days: 1))
    #expect(plan.entries[1].snapshot?.eaten == .zero)
    #expect(plan.entries[1].snapshot?.targets == targets)
    // Refreshed just after midnight, not before it.
    #expect(plan.refreshAt > midnight && plan.refreshAt.timeIntervalSince(midnight) <= 5)
  }

  @Test func yesterdaysSnapshotIsAnEmptyTodayAgainstTheSameTargets() {
    let plan = TodayMacrosTimeline.plan(
      snapshot: snapshot(day: today.adding(days: -1), calories: 1900, targets: targets),
      now: noon, calendar: utc)
    #expect(plan.entries[0].snapshot?.day == today)
    #expect(plan.entries[0].snapshot?.eaten == .zero)
    #expect(plan.entries[0].snapshot?.targets == targets)
  }

  @Test func theWidgetsOwnCalendarDecidesWhatTodayIs() {
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
    // 12:00 UTC on the 10th is 21:00 on the 10th in Tokyo, but 20:00 UTC on the 10th is the 11th.
    let lateInTokyo = utc.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 20))!
    let plan = TodayMacrosTimeline.plan(
      snapshot: snapshot(calories: 700), now: lateInTokyo, calendar: tokyo)
    #expect(plan.entries[0].snapshot?.day == today.adding(days: 1))
    #expect(plan.entries[0].snapshot?.eaten == .zero)
  }

  @Test func buddhistCalendarMatchesGregorianKeyedSnapshot() throws {
    let zone = try #require(TimeZone(identifier: "Pacific/Auckland"))
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = zone
    let localNoon = try #require(
      DayKeyCalendar.make(timeZone: zone).date(
        from: DateComponents(year: 2026, month: 10, day: 10, hour: 12)))
    let plan = TodayMacrosTimeline.plan(
      snapshot: snapshot(calories: 700), now: localNoon, calendar: buddhist)
    #expect(plan.entries[0].snapshot?.day == today)
    #expect(plan.entries[0].snapshot?.eaten.calories == 700)
  }

  @Test func noSnapshotIsNoData() {
    let plan = TodayMacrosTimeline.plan(snapshot: nil, now: noon, calendar: utc)
    #expect(plan.entries.count == 2 && plan.entries.allSatisfy { $0.snapshot == nil })
  }
}

// MARK: Writing

@MainActor
@Suite("Today's macros writing")
struct TodayMacrosWritingTests {
  private let container: ModelContainer
  private let context: ModelContext
  private let folder: ScratchFolder
  private let publisher: TodayMacrosPublisher
  private let reloads: Reloads

  /// Counts the times the widget was asked to redraw.
  @MainActor
  final class Reloads {
    var count = 0
  }

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
    folder = try ScratchFolder()
    let reloads = Reloads()
    self.reloads = reloads
    publisher = TodayMacrosPublisher(
      folder: folder.url, now: { noon }, calendar: utc, reload: { reloads.count += 1 })
  }

  private var editor: DiaryEditor { DiaryEditor(context: context, widget: publisher) }
  private var written: TodayMacrosSnapshot? { TodayMacrosFile.read(from: folder.url) }

  private func newEntry(_ calories: Double, pending: Bool = false) -> NewEntry {
    NewEntry(
      name: "Soup", macros: Macros(calories: calories, protein: 10, carbs: 20, fat: 5),
      source: .manual, macrosPending: pending)
  }

  @Test func nothingIsWrittenUntilSomethingChanges() {
    #expect(written == nil && reloads.count == 0)
  }

  @Test func loggingFoodWritesTheNewTotalsAndRedrawsTheWidget() throws {
    let added = try editor.add([newEntry(300)], on: today, slot: .lunch)
    #expect(written?.eaten.calories == 300)
    #expect(reloads.count == 1)

    try editor.add([newEntry(200)], on: today, slot: .dinner)
    #expect(written?.eaten.calories == 500)
    #expect(reloads.count == 2)
    #expect(added.count == 1)
  }

  @Test func changingRemovingAndRestoringAnEntryEachWriteAgain() throws {
    let record = try #require(try editor.add([newEntry(300)], on: today, slot: .lunch).first)

    var draft = EntryDraft(record)
    draft.servings = "2"
    let valid = try #require(draft.valid(requireCalories: false))
    try editor.update(record, with: valid)
    #expect(written?.eaten.calories == 600)

    let removed = try editor.remove(record)
    #expect(written?.eaten.calories == 0)

    try editor.restore(removed)
    #expect(written?.eaten.calories == 600)
    #expect(reloads.count == 4)
  }

  @Test func aRefusedChangeWritesNothing() throws {
    let bad = NewEntry(name: "", macros: .none, source: .manual)
    #expect(throws: DiaryWrites.Failure.invalid) {
      try editor.add([bad], on: today, slot: .lunch)
    }
    #expect(written == nil && reloads.count == 0)
  }

  @Test func aWaitingMealIsFlaggedUntilTheQueueFillsItIn() async throws {
    try editor.add([newEntry(0, pending: true)], on: today, slot: .lunch)
    #expect(written?.hasWaitingEntry == true)

    let record = try #require(try context.fetch(FetchDescriptor<DiaryEntryRecord>()).first)
    record.macros = .none
    AIJobQueue.enqueueMeal("two eggs", for: record, in: context)
    try context.save()
    let ai = MealStub(calories: 243)
    #expect(await AIQueueRunner.drain(in: context, using: ai, widget: publisher) == 1)
    #expect(written?.hasWaitingEntry == false)
    #expect(written?.eaten.calories == 243)
  }

  @Test func aQueueThatGaveUpStillClearsTheNote() async throws {
    try editor.add([newEntry(0, pending: true)], on: today, slot: .lunch)
    let record = try #require(try context.fetch(FetchDescriptor<DiaryEntryRecord>()).first)
    record.macrosPending = false
    try context.save()
    #expect(
      await AIQueueRunner.drain(in: context, using: MealStub(calories: 1), widget: publisher) == 0)
    #expect(written?.hasWaitingEntry == false)
  }

  @Test func savingTheTargetsWritesThem() throws {
    var form = TargetsForm(today: today)
    form.sex = .female
    form.birthDate = LocalDate(year: 1990, month: 5, day: 14)
    form.cm = "168"
    form.weight = "74.2"
    form.activity = .light
    form.choose(goal: .lose)
    #expect(written == nil)
    try form.save(in: context, publishing: publisher)
    #expect(written?.targets == MacroTargets(calories: 1450, protein: 134, carbs: 129, fat: 45))
    #expect(reloads.count == 1)

    // Changing one by hand writes the change.
    form.overrides[.calories] = "1600"
    try form.save(in: context, publishing: publisher)
    #expect(written?.targets?.calories == 1600)
  }

  @Test func acceptingACheckInWritesTheNewTargets() throws {
    try DebugSeed.populate(context, today: today)
    let inputs = try CheckInInputs.gather(from: context, today: today)
    let check = try #require(inputs.build(keepOverrides: true))
    try CheckInWrites.accept(
      check, keepOverrides: true, today: today, in: context, publishing: publisher)
    let row = try #require(try context.current(TargetsRecord.self))
    #expect(written?.targets == row.macroTargets)
    #expect(reloads.count == 1)
  }

  @Test func whenTheTargetsAreOnlyDeferredNothingIsWritten() throws {
    try DebugSeed.populate(context, today: today)
    try CheckInWrites.dismiss(today: today, in: context)
    #expect(written == nil)
  }

  @Test func theFolderMayBeGoneAndTheAppCarriesOn() throws {
    let gone = TodayMacrosPublisher(
      folder: folder.url.appending(path: "missing", directoryHint: .isDirectory),
      now: { noon }, calendar: utc)
    #expect(!gone.publish(from: context))
  }

  @Test func underTestNothingReachesTheRealContainer() throws {
    // The shared publisher has no folder in a test run, whatever the signing.
    #expect(CauldronStore.launchMode == .inMemory)
    #expect(!TodayMacrosPublisher.shared.publish(from: context))
    // So a write made the way the app makes it leaves the real file as it was.
    let live = TodayMacrosFile.liveFolder()
    let before = TodayMacrosFile.read(from: live)
    try DiaryEditor(context: context).add([newEntry(777)], on: today, slot: .lunch)
    #expect(TodayMacrosFile.read(from: live) == before)
  }
}

private struct MealStub: RecipeAI {
  let calories: Double

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    throw .unreachable
  }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    throw .unreachable
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    [DescribedItem(name: "Eggs", amount: nil, macros: Macros(calories: calories))]
  }
}

// MARK: Opening the diary from the widget

@MainActor
@Suite("Widget link")
struct AppLinkTests {
  @Test func theWidgetsLinkOpensTheTrackerOnToday() throws {
    let link = try #require(AppLink(url: AppLink.todayDiary.url))
    #expect(link == .todayDiary)
    #expect(link.destination == .tracker)
    #expect(AppLink.todayDiary.url.absoluteString == "cauldron://tracker/today")
  }

  @Test func theLinkIsAcceptedInEitherCase() throws {
    #expect(AppLink(url: try #require(URL(string: "Cauldron://Tracker/today"))) == .todayDiary)
    #expect(AppLink(url: try #require(URL(string: "cauldron://tracker/today/"))) == .todayDiary)
  }

  @Test(
    "other addresses open nothing",
    arguments: [
      "https://tracker/today", "cauldron://tracker", "cauldron://recipes/today",
      "cauldron://tracker/yesterday", "cauldron:///today",
      "computer.srcery.cauldron://tracker/today",
    ])
  func otherAddresses(_ address: String) throws {
    #expect(AppLink(url: try #require(URL(string: address))) == nil)
  }

  @Test func theTrackerIsRebuiltEachTimeSoItReturnsToToday() throws {
    let container = try CauldronStore.container(.inMemory)
    for visit in [0, 1] {
      let view = AppDestinationView(destination: .tracker, visit: visit)
        .environment(SyncStatusModel(account: FakeICloudAccount(.synced)))
        .environment(HealthSync.disabled())
        .modelContainer(container)
        .frame(width: 390, height: 800)
      #expect(ImageRenderer(content: view).cgImage != nil)
    }
  }
}

// MARK: Drawing

@MainActor
@Suite("Today's macros widget")
struct TodayMacrosWidgetViewTests {
  private struct Case {
    var name: String
    var snapshot: TodayMacrosSnapshot?
  }

  private static let cases: [Case] = [
    Case(name: "targets", snapshot: snapshot(calories: 1240, targets: targets)),
    Case(name: "over", snapshot: snapshot(calories: 2600, targets: targets)),
    Case(name: "no targets", snapshot: snapshot(calories: 1240)),
    Case(name: "waiting", snapshot: snapshot(calories: 640, targets: targets, waiting: true)),
    Case(name: "nothing eaten", snapshot: snapshot(calories: 0, targets: targets)),
    Case(name: "no data", snapshot: nil),
  ]

  private static var families: [WidgetFamily] {
    #if os(iOS)
      [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular]
    #else
      [.systemSmall, .systemMedium]
    #endif
  }

  private func size(of family: WidgetFamily) -> CGSize {
    switch family {
    case .systemMedium: CGSize(width: 329, height: 155)
    case .accessoryCircular: CGSize(width: 76, height: 76)
    case .accessoryRectangular: CGSize(width: 172, height: 76)
    default: CGSize(width: 158, height: 158)
    }
  }

  private func draws(_ item: Case, in family: WidgetFamily, _ scheme: ColorScheme) -> Bool {
    let view = TodayMacrosContent(
      entry: TodayMacrosEntry(date: noon, snapshot: item.snapshot), family: family
    )
    .environment(\.colorScheme, scheme)
    .frame(width: size(of: family).width, height: size(of: family).height)
    return ImageRenderer(content: view).cgImage != nil
  }

  @Test func everyFamilyDrawsEveryStateInBothAppearances() {
    for family in Self.families {
      for item in Self.cases {
        for scheme in [ColorScheme.light, .dark] {
          #expect(draws(item, in: family, scheme), "\(item.name), \(family), \(scheme)")
        }
      }
    }
  }

  @Test func theSpokenSummaryNamesEachMacroAgainstItsTarget() {
    let spoken = TodayMacrosSpeech.label(for: snapshot(calories: 1240, targets: targets))
    let eaten = TodayMacrosMeter.whole(1240)
    let target = TodayMacrosMeter.whole(2000)
    #expect(spoken.hasPrefix("Eaten against target, Calories \(eaten) kcal of \(target)"))
    #expect(spoken.contains("Protein 50 g of 140"))
    #expect(!spoken.contains("Targets aren't set"))
  }

  @Test func theSpokenSummarySaysWhenTargetsAreMissingAndAMealIsWaiting() {
    let spoken = TodayMacrosSpeech.label(for: snapshot(waiting: true))
    #expect(spoken.contains(Copy.tracker.widget.noTargets.text))
    #expect(spoken.contains(Copy.tracker.widget.estimating.text))
    #expect(TodayMacrosSpeech.label(for: nil) == Copy.tracker.widget.noData.text)
  }
}
