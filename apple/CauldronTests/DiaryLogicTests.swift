import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Diary day")
struct DayLogTests {
  private let day = LocalDate(year: 2026, month: 10, day: 10)!

  private func entry(
    _ name: String, _ slot: MealSlot, position: Int, servings: Double = 1, kcal: Double? = nil,
    protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil
  ) -> DiaryEntry {
    DiaryEntry(
      id: UUID(), date: day, slot: slot, name: name, amount: nil, servings: servings,
      macros: Macros(calories: kcal, protein: protein, carbs: carbs, fat: fat), source: .manual,
      recipeId: nil, position: position)
  }

  @Test func anEmptyDayHasFourEmptyMeals() {
    let log = DayLog(day: day, entries: [])
    #expect(log.sections.map(\.slot) == [.breakfast, .lunch, .dinner, .snack])
    #expect(log.isEmpty)
    #expect(log.totals == .zero)
    #expect(log.sections.allSatisfy { $0.subtotal == .zero })
  }

  @Test func entriesSitInTheirMealInPositionOrder() {
    let log = DayLog(
      day: day,
      entries: [
        entry("Dinner b", .dinner, position: 1), entry("Toast", .breakfast, position: 0),
        entry("Dinner a", .dinner, position: 0), entry("Eggs", .breakfast, position: 1),
      ])
    #expect(log.sections[0].entries.map(\.name) == ["Toast", "Eggs"])
    #expect(log.sections[1].entries.isEmpty)
    #expect(log.sections[2].entries.map(\.name) == ["Dinner a", "Dinner b"])
    #expect(!log.isEmpty)
  }

  @Test func subtotalsAndTotalsMultiplyByServingsAndSkipUnknowns() {
    let log = DayLog(
      day: day,
      entries: [
        entry(
          "Eggs", .breakfast, position: 0, servings: 2, kcal: 143, protein: 12.5, carbs: 1, fat: 9.5
        ),
        entry("Toast", .breakfast, position: 1, kcal: 100, protein: 4, carbs: 19, fat: 1),
        // Only calories known: the rest add nothing.
        entry("Mystery", .snack, position: 0, servings: 0.5, kcal: 200),
      ])
    #expect(log.sections[0].subtotal == MacroTotals(calories: 386, protein: 29, carbs: 21, fat: 20))
    #expect(log.sections[3].subtotal == MacroTotals(calories: 100, protein: 0, carbs: 0, fat: 0))
    #expect(log.totals == MacroTotals(calories: 486, protein: 29, carbs: 21, fat: 20))
  }

  @Test func twoEntriesWithTheSamePositionKeepOneOrderEverywhere() {
    var a = entry("A", .lunch, position: 0)
    var b = entry("B", .lunch, position: 0)
    a.id = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    b.id = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    #expect(DayLog(day: day, entries: [b, a]).sections[1].entries.map(\.name) == ["A", "B"])
    #expect(DayLog(day: day, entries: [a, b]).sections[1].entries.map(\.name) == ["A", "B"])
  }

  @Test func storedRowsAreOrderedByAddedTimeWhenPositionsClash() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let early = DiaryEntryRecord(day: day, slot: .lunch, name: "Early", source: .manual)
    early.createdAt = Date(timeIntervalSince1970: 1000)
    let late = DiaryEntryRecord(day: day, slot: .lunch, name: "Late", source: .manual)
    late.createdAt = Date(timeIntervalSince1970: 2000)
    for record in [late, early] { context.insert(record) }
    let log = DayLog(day: day, records: [late, early])
    #expect(log.sections[1].entries.map(\.name) == ["Early", "Late"])
  }

  @Test func aRealSeededDayAddsUpLikeTheRowsDo() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    try DebugSeed.populate(context, today: day)
    // The fullest day of the four weeks.
    let all = try context.fetch(FetchDescriptor<DiaryEntryRecord>())
    let busiest = try #require(
      Dictionary(grouping: all, by: \.dayKey).max { $0.value.count < $1.value.count })
    let seeded = try #require(LocalDate(busiest.key))
    let rows = busiest.value
    #expect(rows.count > 2)

    let log = DayLog(day: seeded, records: rows)
    var kcal = 0.0
    var protein = 0.0
    for row in rows {
      kcal += (row.calories ?? 0) * row.servings
      protein += (row.protein ?? 0) * row.servings
    }
    #expect(abs(log.totals.calories - kcal) < 1e-9)
    #expect(abs(log.totals.protein - protein) < 1e-9)
    #expect(log.sections.map(\.entries.count).reduce(0, +) == rows.count)
    // The meals add up to the day.
    #expect(abs(log.sections.map(\.subtotal.calories).reduce(0, +) - kcal) < 1e-9)
  }
}

@Suite("Eaten against target")
struct MacroMeterTests {
  private let totals = MacroTotals(calories: 386, protein: 150, carbs: 21, fat: 20)
  private let targets = MacroTargets(calories: 1450, protein: 134, carbs: 129, fat: 45)

  @Test func fourMetersCaloriesFirst() {
    let meters = MacroMeter.meters(totals: totals, targets: targets)
    #expect(meters.map(\.key) == [.calories, .protein, .carbs, .fat])
    #expect(meters.map(\.target) == [1450, 134, 129, 45])
  }

  @Test func underTargetShowsWhatIsLeft() {
    let carbs = MacroMeter.meters(totals: totals, targets: targets)[2]
    #expect(!carbs.isOver)
    #expect(carbs.remaining == 108)
    #expect(carbs.leftText?.text == "108 g left")
    #expect(carbs.eatenText == "21")
    #expect(carbs.targetText == "129")
    #expect(abs(carbs.fill - 21.0 / 129.0) < 1e-12)
    #expect(carbs.overFill == 0)
  }

  @Test func overTargetShowsHowFarOver() {
    let protein = MacroMeter.meters(totals: totals, targets: targets)[1]
    #expect(protein.isOver)
    #expect(protein.leftText?.text == "16 g over")
    #expect(protein.fill == 1)
    #expect(abs(protein.overFill - (150.0 / 134.0 - 1)) < 1e-12)
  }

  @Test func theOverBarNeverPassesTheTrack() {
    let meter = MacroMeter(key: .fat, eaten: 500, target: 45)
    #expect(meter.fill == 1 && meter.overFill == 1)
  }

  @Test func exactlyOnTargetIsNeitherLeftNorOver() {
    let meter = MacroMeter(key: .protein, eaten: 134, target: 134)
    #expect(!meter.isOver)
    #expect(meter.leftText?.text == "0 g left")
  }

  @Test func withoutTargetsThereIsNothingToCompare() {
    let meters = MacroMeter.meters(totals: totals, targets: nil)
    #expect(meters.allSatisfy { $0.target == nil && $0.leftText == nil && $0.fraction == 0 })
    #expect(meters[0].eatenText == "386")
    #expect(meters[0].targetText == nil)
  }

  @Test func aTargetOfZeroFillsNothing() {
    let meter = MacroMeter(key: .fat, eaten: 10, target: 0)
    #expect(meter.fraction == 0 && meter.fill == 0)
    #expect(meter.isOver)
  }

  @Test func caloriesAreInKcalAndTheRestInGrams() {
    #expect(MacroMeter(key: .calories, eaten: 0, target: 1).unit.text == "kcal")
    #expect(MacroMeter(key: .carbs, eaten: 0, target: 1).unit.text == "g")
    #expect(MacroMeter(key: .calories, eaten: 5, target: 10).leftText?.text == "5 kcal left")
  }
}

@Suite("Entry draft")
struct EntryDraftTests {
  private func typed(
    name: String = "Flat white", servings: String = "1", calories: String = "120",
    slot: MealSlot = .snack
  ) -> EntryDraft {
    var draft = EntryDraft(slot: slot)
    draft.name = name
    draft.servings = servings
    draft.calories = calories
    return draft
  }

  @Test func aBlankDraftNeedsAName() {
    let errors = EntryDraft(slot: .lunch).errors(requireCalories: false)
    #expect(errors == [.name: Copy.validation.required])
    #expect(EntryDraft(slot: .lunch).valid(requireCalories: false) == nil)
  }

  @Test func aQuickAddNeedsCaloriesButAnEditDoesNot() {
    let draft = typed(calories: "")
    #expect(draft.errors(requireCalories: true)[.macro(.calories)] == Copy.validation.required)
    #expect(draft.errors(requireCalories: false).isEmpty)
    #expect(draft.valid(requireCalories: false)?.macros.calories == nil)
  }

  @Test func typedTextBecomesRoundedNumbers() {
    var draft = typed(servings: " 0,5 ", calories: "120.4")
    draft.name = "  Flat white "
    draft.amount = " 1 cup "
    draft.protein = "3.14"
    draft.carbs = "11,96"
    draft.fat = ""
    let valid = draft.valid(requireCalories: true)
    #expect(valid?.name == "Flat white")
    #expect(valid?.amount == "1 cup")
    #expect(valid?.servings == 0.5)
    #expect(valid?.macros == Macros(calories: 120, protein: 3.1, carbs: 12, fat: nil))
    #expect(valid?.slot == .snack)
  }

  @Test func aBlankAmountIsNoAmount() {
    var draft = typed()
    draft.amount = "   "
    #expect(draft.valid(requireCalories: false)?.amount == nil)
  }

  @Test(
    "servings must be above 0 and at most 100",
    arguments: ["0", "-1", "101", "abc", "", "inf", "nan"])
  func badServings(_ text: String) {
    let draft = typed(servings: text)
    #expect(draft.errors(requireCalories: false)[.servings]?.text == "Use a number from 0 to 100.")
    #expect(draft.valid(requireCalories: false) == nil)
  }

  @Test func theServingsLimitsThemselvesAreFine() {
    #expect(typed(servings: "100").valid(requireCalories: false)?.servings == 100)
    #expect(typed(servings: "0.01").valid(requireCalories: false)?.servings == 0.01)
  }

  @Test(
    "calories must be a whole number up to the limit",
    arguments: ["-1", "20001", "abc", "1e999", "nan"])
  func badCalories(_ text: String) {
    let draft = typed(calories: text)
    #expect(
      draft.errors(requireCalories: false)[.macro(.calories)]?.text
        == "Use a whole number from 0 to 20000.")
    #expect(draft.valid(requireCalories: false) == nil)
  }

  @Test func gramsHaveALimitToo() {
    for key in [MacroKey.protein, .carbs, .fat] {
      var draft = typed()
      draft[macro: key] = "2000.04"
      #expect(draft.valid(requireCalories: false) != nil, "\(key) at the limit")
      draft[macro: key] = "2001"
      #expect(
        draft.errors(requireCalories: false)[.macro(key)]?.text == "Use a number from 0 to 2000.")
      draft[macro: key] = "-3"
      #expect(draft.valid(requireCalories: false) == nil, "\(key) below 0")
    }
  }

  @Test func nameAndAmountHaveALength() {
    var draft = typed(name: String(repeating: "x", count: 201))
    draft.amount = String(repeating: "y", count: 101)
    let errors = draft.errors(requireCalories: false)
    #expect(errors[.name]?.text == "Keep it to 200 characters or fewer.")
    #expect(errors[.amount]?.text == "Keep it to 100 characters or fewer.")
    draft.name = String(repeating: "x", count: 200)
    draft.amount = String(repeating: "y", count: 100)
    #expect(draft.valid(requireCalories: false) != nil)
  }

  @Test func theServingButtonsStepByAQuarterAndStopAtAQuarter() {
    var draft = typed(servings: "1")
    draft.nudgeServings(by: EntryDraft.servingStep)
    #expect(draft.servings == "1.25")
    draft.nudgeServings(by: -EntryDraft.servingStep * 10)
    #expect(draft.servings == "0.25")
    draft.servings = "abc"
    draft.nudgeServings(by: EntryDraft.servingStep)
    #expect(draft.servings == "1.25")
  }

  @MainActor
  @Test func anEntryOpensAsItsOwnText() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let day = LocalDate(year: 2026, month: 10, day: 10)!
    let record = DiaryEntryRecord(
      day: day, slot: .dinner, name: "Soup", servings: 1.5, source: .manual)
    record.amount = "1 bowl"
    record.macros = Macros(calories: 210, protein: 8.5, carbs: nil, fat: 6)
    context.insert(record)

    let draft = EntryDraft(record)
    #expect(draft.name == "Soup" && draft.amount == "1 bowl" && draft.servings == "1.5")
    #expect(
      draft.calories == "210" && draft.protein == "8.5" && draft.carbs == "" && draft.fat == "6")
    #expect(draft.slot == .dinner)
    // Unchanged, it saves as the same numbers.
    let valid = try #require(draft.valid(requireCalories: false))
    #expect(valid.macros == record.macros && valid.servings == 1.5)
  }
}

@MainActor
@Suite("Diary writes")
struct DiaryWritesTests {
  private let day = LocalDate(year: 2026, month: 10, day: 10)!
  private let container: ModelContainer
  private let context: ModelContext

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
  }

  private func food(_ name: String, kcal: Double = 100) -> NewEntry {
    NewEntry(name: name, macros: Macros(calories: kcal), source: .manual)
  }

  private func rows(_ day: LocalDate? = nil, slot: MealSlot? = nil) throws -> [DiaryEntryRecord] {
    let all = try context.fetch(FetchDescriptor<DiaryEntryRecord>())
    return all.filter { ($0.day == (day ?? self.day)) && (slot == nil || $0.slot == slot) }
      .sorted { $0.position < $1.position }
  }

  @Test func anEntryGoesLastInItsMeal() throws {
    try DiaryWrites.add([food("Toast")], on: day, slot: .breakfast, in: context)
    try DiaryWrites.add([food("Eggs")], on: day, slot: .breakfast, in: context)
    try DiaryWrites.add([food("Soup")], on: day, slot: .lunch, in: context)
    #expect(try rows(slot: .breakfast).map(\.name) == ["Toast", "Eggs"])
    #expect(try rows(slot: .breakfast).map(\.position) == [0, 1])
    #expect(try rows(slot: .lunch).map(\.position) == [0])
  }

  @Test func theNumbersAreCopiedIntoTheEntry() throws {
    let added = try DiaryWrites.add(
      [
        NewEntry(
          name: " Soup ", amount: "1 bowl", servings: 1.5,
          macros: Macros(calories: 210, protein: 8, carbs: nil, fat: 6), source: .described)
      ], on: day, slot: .dinner, in: context)
    let record = try #require(added.first)
    #expect(record.name == "Soup" && record.amount == "1 bowl" && record.servings == 1.5)
    #expect(record.macros == Macros(calories: 210, protein: 8, carbs: nil, fat: 6))
    #expect(record.source == .described && record.slot == .dinner && record.day == day)
  }

  @Test func aBatchLandsInOrderAndAllOrNone() throws {
    try DiaryWrites.add([food("A"), food("B"), food("C")], on: day, slot: .snack, in: context)
    #expect(try rows().map(\.name) == ["A", "B", "C"])
    #expect(try rows().map(\.position) == [0, 1, 2])
  }

  @Test func aFullDayTakesNoMore() throws {
    let many = (0..<TrackerLimits.perDay).map { food("Food \($0)") }
    try DiaryWrites.add(many, on: day, slot: .snack, in: context)
    #expect(try DiaryWrites.count(on: day, in: context) == 100)
    #expect(throws: DiaryWrites.Failure.dayFull) {
      try DiaryWrites.add([self.food("One more")], on: day, slot: .lunch, in: context)
    }
    #expect(try DiaryWrites.count(on: day, in: context) == 100)
    // Another day is unaffected.
    try DiaryWrites.add([food("Fine")], on: day.adding(days: 1), slot: .lunch, in: context)
  }

  @Test func aBatchThatWouldOverfillTheDayAddsNothing() throws {
    try DiaryWrites.add(
      (0..<98).map { food("Food \($0)") }, on: day, slot: .snack, in: context)
    #expect(throws: DiaryWrites.Failure.dayFull) {
      try DiaryWrites.add(
        [self.food("a"), self.food("b"), self.food("c")], on: day, slot: .lunch, in: context)
    }
    #expect(try DiaryWrites.count(on: day, in: context) == 98)
  }

  @Test func numbersTheStoreWouldRefuseNeverArrive() throws {
    let bad: [NewEntry] = [
      NewEntry(name: "x", servings: .nan, macros: Macros(), source: .manual),
      NewEntry(name: "x", servings: .infinity, macros: Macros(), source: .manual),
      NewEntry(name: "x", servings: 0, macros: Macros(), source: .manual),
      NewEntry(name: "x", servings: 101, macros: Macros(), source: .manual),
      NewEntry(name: "x", macros: Macros(calories: .nan), source: .manual),
      NewEntry(name: "x", macros: Macros(calories: .infinity), source: .manual),
      NewEntry(name: "x", macros: Macros(calories: -1), source: .manual),
      NewEntry(name: "x", macros: Macros(calories: 20_001), source: .manual),
      NewEntry(name: "x", macros: Macros(protein: 2001), source: .manual),
      NewEntry(name: "x", macros: Macros(fat: -0.5), source: .manual),
      NewEntry(name: "   ", macros: Macros(), source: .manual),
    ]
    for entry in bad {
      #expect(throws: DiaryWrites.Failure.invalid) {
        try DiaryWrites.add([entry], on: day, slot: .lunch, in: context)
      }
    }
    // One bad entry spoils the batch.
    #expect(throws: DiaryWrites.Failure.invalid) {
      try DiaryWrites.add([food("fine"), bad[0]], on: day, slot: .lunch, in: context)
    }
    #expect(try DiaryWrites.count(on: day, in: context) == 0)
  }

  private func valid(
    _ record: DiaryEntryRecord, change: (inout EntryDraft) -> Void
  ) throws -> EntryDraft.Valid {
    var draft = EntryDraft(record)
    change(&draft)
    return try #require(draft.valid(requireCalories: false))
  }

  @Test func editingChangesTheFieldsAndKeepsTheOrder() throws {
    let added = try DiaryWrites.add(
      [food("Toast"), food("Eggs")], on: day, slot: .breakfast, in: context)
    let eggs = added[1]
    let change = try valid(eggs) {
      $0.name = "Scrambled eggs"
      $0.servings = "2"
      $0.calories = "143"
      $0.protein = "12.5"
      $0.amount = "2 large"
    }
    try DiaryWrites.update(eggs, with: change, in: context)
    #expect(eggs.name == "Scrambled eggs" && eggs.servings == 2 && eggs.amount == "2 large")
    #expect(eggs.macros == Macros(calories: 143, protein: 12.5, carbs: nil, fat: nil))
    #expect(eggs.position == 1 && eggs.slot == .breakfast)
  }

  @Test func movingToAnotherMealPutsItLastThere() throws {
    let toast = try DiaryWrites.add(
      [food("Toast"), food("Eggs")], on: day, slot: .breakfast, in: context)[0]
    try DiaryWrites.add([food("Soup"), food("Salad")], on: day, slot: .lunch, in: context)
    try DiaryWrites.update(toast, with: valid(toast) { $0.slot = .lunch }, in: context)
    #expect(try rows(slot: .lunch).map(\.name) == ["Soup", "Salad", "Toast"])
    #expect(try rows(slot: .lunch).map(\.position) == [0, 1, 2])
    #expect(try rows(slot: .breakfast).map(\.name) == ["Eggs"])
    #expect(toast.day == day)
  }

  @Test func movingToAnEmptyMealStartsItAtZero() throws {
    let toast = try DiaryWrites.add([food("Toast")], on: day, slot: .breakfast, in: context)[0]
    try DiaryWrites.update(toast, with: valid(toast) { $0.slot = .dinner }, in: context)
    #expect(toast.position == 0 && toast.slot == .dinner)
  }

  @Test func aRefusedEditLeavesTheEntryAsItWas() throws {
    let toast = try DiaryWrites.add([food("Toast")], on: day, slot: .breakfast, in: context)[0]
    let tooMany = EntryDraft.Valid(
      name: "Toast", amount: nil, servings: .nan, macros: Macros(calories: 100), slot: .lunch)
    #expect(throws: DiaryWrites.Failure.invalid) {
      try DiaryWrites.update(toast, with: tooMany, in: context)
    }
    #expect(toast.servings == 1 && toast.slot == .breakfast)
  }

  @Test func deletingLeavesTheRestWhereTheyWereAndTheNextGoesLast() throws {
    let added = try DiaryWrites.add(
      [food("A"), food("B"), food("C")], on: day, slot: .lunch, in: context)
    try DiaryWrites.remove(added[1], in: context)
    #expect(try rows().map(\.name) == ["A", "C"])
    #expect(try rows().map(\.position) == [0, 2])
    try DiaryWrites.add([food("D")], on: day, slot: .lunch, in: context)
    #expect(try rows().map(\.name) == ["A", "C", "D"])
    // The day reads back in that order.
    let log = DayLog(day: day, records: try rows())
    #expect(log.sections[1].entries.map(\.name) == ["A", "C", "D"])
  }

  @Test func deletingTheLastEntryEmptiesTheDay() throws {
    let only = try DiaryWrites.add([food("A")], on: day, slot: .lunch, in: context)[0]
    try DiaryWrites.remove(only, in: context)
    #expect(try DiaryWrites.count(on: day, in: context) == 0)
    #expect(DayLog(day: day, records: try rows()).isEmpty)
  }

  @Test func theHeaderNumbersFollowEveryEdit() throws {
    let target = MacroTargets(calories: 1450, protein: 134, carbs: 129, fat: 45)
    func eaten() throws -> Double {
      MacroMeter.meters(totals: DayLog(day: day, records: try rows()).totals, targets: target)[0]
        .eaten
    }
    let soup = try DiaryWrites.add([food("Soup", kcal: 300)], on: day, slot: .lunch, in: context)[0]
    #expect(try eaten() == 300)
    try DiaryWrites.update(soup, with: valid(soup) { $0.servings = "2" }, in: context)
    #expect(try eaten() == 600)
    try DiaryWrites.remove(soup, in: context)
    #expect(try eaten() == 0)
  }

  @Test func aSeededDayTakesMoreAfterTheRealOnes() throws {
    try DebugSeed.populate(context, today: day)
    let before = try rows(slot: .snack).map(\.position).max() ?? -1
    let added = try DiaryWrites.add([food("Extra")], on: day, slot: .snack, in: context)
    #expect(added[0].position == before + 1)
  }
}
