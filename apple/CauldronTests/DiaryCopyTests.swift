import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

/// Copying a diary day or one meal into another day. Ported case for case from "copy a day" in
/// `apps/api/test/tracker-quick.test.ts`.
@MainActor
@Suite("Copy a diary day")
struct DiaryCopyTests {
  private let from = LocalDate(year: 2026, month: 6, day: 1)!
  private let to = LocalDate(year: 2026, month: 6, day: 2)!
  private let container: ModelContainer
  private let context: ModelContext

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
  }

  @discardableResult
  private func log(
    _ name: String, on day: LocalDate? = nil, slot: MealSlot = .breakfast, amount: String? = nil,
    servings: Double = 1, kcal: Double? = 100, source: DiarySource = .manual,
    recipe: RecipeRecord? = nil, pending: Bool = false
  ) throws -> DiaryEntryRecord {
    try DiaryWrites.add(
      [
        NewEntry(
          name: name, amount: amount, servings: servings,
          macros: kcal.map { Macros(calories: $0, protein: 5, carbs: 10, fat: 2) } ?? .none,
          source: source, recipe: recipe, macrosPending: pending)
      ], on: day ?? from, slot: slot, in: context)[0]
  }

  private func records(on day: LocalDate) throws -> [DiaryEntryRecord] {
    let key = day.description
    let found = try context.fetch(
      FetchDescriptor<DiaryEntryRecord>(predicate: #Predicate { $0.dayKey == key }))
    return DayLog(day: day, records: found).sections.flatMap(\.entries).compactMap { entry in
      found.first { $0.id == entry.id }
    }
  }

  private func fill(_ day: LocalDate, count: Int, prefix: String) throws {
    try DiaryWrites.add(
      (0..<count).map {
        NewEntry(name: "\(prefix) \($0)", macros: .none, source: .manual)
      }, on: day, slot: .snack, in: context)
  }

  // MARK: Cases from the web

  @Test func copiesEveryEntryIntoTheSameMealsWithTheSameNumbers() throws {
    let recipe = RecipeRecord(title: "Soup")
    context.insert(recipe)
    try log("Oats", amount: "1 bowl", servings: 1.5)
    try log("Toast")
    try log("Soup", slot: .dinner, servings: 2, source: .recipe, recipe: recipe)
    try log("Apple", slot: .snack, source: .described)

    let copies = try DiaryWrites.copy(from: from, to: to, in: context)
    #expect(copies.count == 4)
    let source = try records(on: from)
    let copied = try records(on: to)
    #expect(source.count == 4 && copied.count == 4)
    func shape(_ record: DiaryEntryRecord) -> [String] {
      [
        record.slot.rawValue, record.name, record.amount ?? "-", "\(record.servings)",
        "\(record.macros)", record.source.rawValue, record.recipe?.id.uuidString ?? "-",
      ]
    }
    #expect(copied.map(shape) == source.map(shape))
    #expect(copied.allSatisfy { $0.day == to })
    #expect(Set(copied.map(\.id)).count == 4)
    #expect(Set(copied.map(\.id)).isDisjoint(with: source.map(\.id)))
    #expect(DayLog(day: to, records: copied).totals == DayLog(day: from, records: source).totals)
  }

  @Test func appendsAfterWhatTheTargetDayAlreadyHasInEachMeal() throws {
    try log("Existing", on: to)
    try log("Copied")
    try DiaryWrites.copy(from: from, to: to, in: context)
    #expect(try records(on: to).map(\.name) == ["Existing", "Copied"])
    try DiaryWrites.copy(from: from, to: to, in: context)
    #expect(try records(on: to).map(\.name) == ["Existing", "Copied", "Copied"])
    #expect(try records(on: to).map(\.position) == [0, 1, 2])
  }

  @Test func copiesOnlyOneMealWhenAsked() throws {
    try log("Oats")
    try log("Soup", slot: .lunch)
    let copies = try DiaryWrites.copy(from: from, to: to, slot: .lunch, in: context)
    #expect(copies.map { [$0.slot.rawValue, $0.name] } == [["lunch", "Soup"]])
    #expect(try records(on: to).count == 1)
  }

  @Test func anEmptyDayCopiesNothingAndLeavesTheTargetAlone() throws {
    try log("Existing", on: to)
    let empty = LocalDate(year: 2026, month: 6, day: 20)!
    #expect(try DiaryWrites.copy(from: empty, to: to, in: context).isEmpty)
    #expect(try records(on: to).map(\.name) == ["Existing"])
    let other = LocalDate(year: 2026, month: 6, day: 9)!
    #expect(try DiaryWrites.copy(from: empty, to: other, in: context).isEmpty)
    #expect(try records(on: other).isEmpty)
  }

  @Test func aDayCanNotBeCopiedOntoItself() throws {
    try log("Oats")
    #expect(throws: DiaryWrites.Failure.invalid) {
      try DiaryWrites.copy(from: from, to: from, in: context)
    }
    #expect(try records(on: from).count == 1)
  }

  @Test func aCopyThatWouldPassTheDailyLimitCopiesNothing() throws {
    let per = TrackerLimits.perDay
    try fill(from, count: 10, prefix: "src")
    try fill(to, count: per - 5, prefix: "dst")
    #expect(throws: DiaryWrites.Failure.dayFull) {
      try DiaryWrites.copy(from: from, to: to, in: context)
    }
    #expect(try records(on: to).count == per - 5)
  }

  @Test func aCopyCanFillTheDayToExactlyTheLimit() throws {
    let per = TrackerLimits.perDay
    try fill(from, count: 5, prefix: "src")
    try fill(to, count: per - 5, prefix: "dst")
    #expect(try DiaryWrites.copy(from: from, to: to, in: context).count == 5)
    #expect(try records(on: to).count == per)
  }

  // MARK: Native

  @Test func anEntryStillWaitingForAnEstimateCopiesAsWaitingAndIsQueued() throws {
    try log("two eggs and toast", slot: .snack, kcal: nil, source: .described, pending: true)
    let editor = DiaryEditor(context: context)
    let copies = try editor.copy(from: from, to: to)
    let copy = try #require(copies.first)
    #expect(copy.macrosPending && copy.macros == .none && copy.source == .described)
    let jobs = try context.fetch(FetchDescriptor<AIJobRecord>())
    #expect(jobs.count == 1)
    #expect(jobs.first?.kind == .mealEstimate && jobs.first?.diaryEntry === copy)
    #expect(jobs.first?.input == "two eggs and toast")
  }

  @Test func theEditorNeedsNoJobForEntriesWithNumbers() throws {
    try log("Oats")
    try DiaryEditor(context: context).copy(from: from, to: to)
    #expect(try context.fetch(FetchDescriptor<AIJobRecord>()).isEmpty)
  }

  @Test func healthFollowsACopiedDay() async throws {
    let fake = FakeHealthStore()
    let defaults = try #require(UserDefaults(suiteName: "copy-day-\(UUID().uuidString)"))
    let target = to
    let sync = HealthSync(
      store: fake, setup: HealthSetup(isConfigured: true), defaults: defaults,
      now: {
        Calendar.current.date(
          from: DateComponents(year: target.year, month: target.month, day: target.day, hour: 12))
          ?? .now
      })
    await sync.connect()
    try log("Soup", kcal: 200)
    try context.save()
    let copy = try #require(
      try DiaryEditor(context: context, health: sync).copy(from: from, to: to).first)
    await sync.settle()
    let held = await fake.held
    #expect(held[HealthNutrition.syncID(entry: copy.id, nutrient: .energy)]?.value == 200)
  }

  @Test func theOutcomeSaysHowManyWentInOrThatThereWasNothing() throws {
    try log("Oats")
    try log("Toast")
    let done = CopyDayOutcome.run(from: from, to: to, slot: nil, in: context)
    #expect(!done.failed && done.message == Copy.tracker.copyDay.copied(2))
    let empty = CopyDayOutcome.run(
      from: LocalDate(year: 2026, month: 6, day: 20)!, to: to, slot: nil, in: context)
    #expect(!empty.failed && empty.message == Copy.tracker.copyDay.nothing)
  }

  @Test func theOutcomeNamesWhyACopyWasRefused() throws {
    try log("Oats")
    let same = CopyDayOutcome.run(from: from, to: from, slot: nil, in: context)
    #expect(same.failed && same.message == Copy.tracker.copyDay.sameDay)

    try fill(to, count: TrackerLimits.perDay, prefix: "dst")
    let full = CopyDayOutcome.run(from: from, to: to, slot: nil, in: context)
    #expect(full.failed && full.message == Copy.tracker.dayFull)
  }

  @Test func theCopySheetDrawsInBothAppearances() {
    for scheme in [ColorScheme.light, .dark] {
      let view = CopyDaySheet(day: to, onClose: {}, onDone: { _, _ in })
        .modelContainer(container)
        .environment(\.colorScheme, scheme)
        .frame(width: 390, height: 700)
      #expect(ImageRenderer(content: view).cgImage != nil, "\(scheme)")
    }
  }

  @Test func theBannerDrawsInBothAppearances() {
    for scheme in [ColorScheme.light, .dark] {
      let view = DiaryMessageBanner(message: Copy.tracker.copyDay.copied(3))
        .environment(\.colorScheme, scheme)
        .frame(width: 390, height: 120)
      #expect(ImageRenderer(content: view).cgImage != nil, "\(scheme)")
    }
  }
}
