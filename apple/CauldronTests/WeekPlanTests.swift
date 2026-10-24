import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Week plan")
struct WeekPlanTests {
  private let monday = LocalDate("2026-10-05")!
  private let en = Locale(identifier: "en_US")

  private func context() throws -> ModelContext {
    ModelContext(try CauldronStore.container(.inMemory))
  }

  private func recipe(
    _ title: String, servings: Int? = 4, macros: Macros = .none, in context: ModelContext
  ) -> RecipeRecord {
    let record = RecipeRecord(title: title)
    record.servings = servings
    record.macros = macros
    context.insert(record)
    return record
  }

  private func titles(_ target: MealTarget, in context: ModelContext) throws -> [String] {
    let all = try context.fetch(FetchDescriptor<PlanEntryRecord>())
    return WeekPlan.inSlot(all, target).map(\.title)
  }

  private func positions(_ target: MealTarget, in context: ModelContext) throws -> [Int] {
    let all = try context.fetch(FetchDescriptor<PlanEntryRecord>())
    return WeekPlan.inSlot(all, target).map(\.position)
  }

  private func dinner(_ day: LocalDate) -> MealTarget { MealTarget(day: day, slot: .dinner) }

  // MARK: Adding

  @Test func stirringARecipeAddsOneEntryPerDayWithItsOwnServings() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let added = try WeekPlan.stir(
      soup,
      days: [
        DayServings(date: monday, servings: 2),
        DayServings(date: monday.adding(days: 1), servings: 1),
      ], slot: .dinner, into: context)
    #expect(added.map(\.dayKey) == ["2026-10-05", "2026-10-06"])
    #expect(added.map(\.servings) == [2, 1])
    #expect(added.allSatisfy { $0.recipe === soup && $0.title == "Soup" && $0.slot == .dinner })
  }

  @Test func stirringIntoOneMealFollowsTheRecipeUnlessToldOtherwise() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let own = try WeekPlan.stir(soup, at: dinner(monday), servings: nil, into: context)
    let six = try WeekPlan.stir(soup, at: dinner(monday), servings: 6, into: context)
    #expect(own.servings == nil && six.servings == 6)
    #expect(try positions(dinner(monday), in: context) == [0, 1])
    #expect(throws: WeekPlanError.invalidServings) {
      try WeekPlan.stir(soup, at: dinner(monday), servings: 0, into: context)
    }
    RecipeLibrary.banish(soup)
    #expect(throws: WeekPlanError.recipeBanished) {
      try WeekPlan.stir(soup, at: dinner(monday), servings: nil, into: context)
    }
    #expect(try titles(dinner(monday), in: context).count == 2)
  }

  @Test func anEntryGoesAfterWhatTheMealAlreadyHolds() throws {
    let context = try context()
    try WeekPlan.stirText("Leftovers", at: dinner(monday), into: context)
    try WeekPlan.stir(
      recipe("Soup", in: context), days: [DayServings(date: monday, servings: 1)],
      slot: .dinner, into: context)
    #expect(try titles(dinner(monday), in: context) == ["Leftovers", "Soup"])
    #expect(try positions(dinner(monday), in: context) == [0, 1])
  }

  @Test func aBanishedRecipeCantBeStirredIn() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    RecipeLibrary.banish(soup)
    #expect(throws: WeekPlanError.recipeBanished) {
      try WeekPlan.stir(
        soup, days: [DayServings(date: monday, servings: 1)], slot: .dinner, into: context)
    }
    #expect(try context.fetchCount(FetchDescriptor<PlanEntryRecord>()) == 0)
  }

  @Test func noDaysAndOutOfRangeServingsAreRefused() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    #expect(throws: WeekPlanError.noDays) {
      try WeekPlan.stir(soup, days: [], slot: .dinner, into: context)
    }
    for servings in [0, WeekLimits.servings + 1] {
      #expect(throws: WeekPlanError.invalidServings) {
        try WeekPlan.stir(
          soup, days: [DayServings(date: monday, servings: servings)], slot: .dinner,
          into: context)
      }
    }
  }

  @Test func batchCreationRejectsBanishedRecipesAndSnapshotsKnownYield() throws {
    let context = try context()
    let soup = recipe("Soup", servings: 4, in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 6, in: context)
    #expect(batch.totalServings == 6)
    #expect(batch.ingredientYield == 4)
    #expect(WeekPlan.assignedServings(batch) == 0)
    #expect(WeekPlan.unassignedServings(batch) == 6)

    RecipeLibrary.banish(soup)
    #expect(throws: WeekPlanError.recipeBanished) {
      try WeekPlan.createBatch(recipe: soup, weekStart: monday, totalServings: 2, in: context)
    }
  }

  @Test func batchAssignmentsRejectCapacityAndOutOfRangeEditsBeforeMutation() throws {
    let context = try context()
    let soup = recipe("Soup", servings: 4, in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 3, in: context)
    let entry = try WeekPlan.assign(2, on: monday, slot: .dinner, to: batch, in: context)
    #expect(throws: WeekPlanError.batchOverAssigned) {
      try WeekPlan.assign(2, on: monday.adding(days: 1), slot: .dinner, to: batch, in: context)
    }
    #expect(throws: WeekPlanError.batchOverAssigned) {
      try WeekPlan.apply(EntryChange(servings: .some(4)), to: entry, in: context)
    }
    #expect(entry.servings == 2)
    #expect(throws: WeekPlanError.batchOverAssigned) {
      try WeekPlan.apply(EntryChange(day: monday.adding(days: 7)), to: entry, in: context)
    }
    #expect(entry.day == monday)
    #expect(WeekPlan.allocation(batch).unassigned == 1)
    #expect(
      WeekPlan.message(for: WeekPlanError.batchOverAssigned).text
        == Copy.week.allocationConflict.text)
  }

  @Test func invalidSyncedBatchEntryIsSurfacedAndCanBeRepairedWithConcreteServings() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 3, in: context)
    let entry = try WeekPlan.assign(2, on: monday, slot: .dinner, to: batch, in: context)
    entry.servings = nil
    #expect(WeekPlan.allocation(batch).hasInvalidEntries)
    try WeekPlan.apply(EntryChange(servings: .some(2)), to: entry, in: context)
    #expect(entry.servings == 2 && !WeekPlan.allocation(batch).hasInvalidEntries)
  }

  @Test func duplicateEntryUUIDStillCountsOtherPersistedAssignmentForCapacity() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 4, in: context)
    let edited = try WeekPlan.assign(2, on: monday, slot: .dinner, to: batch, in: context)
    let other = try WeekPlan.assign(
      2, on: monday.adding(days: 1), slot: .dinner, to: batch, in: context)
    other.id = edited.id
    #expect(throws: WeekPlanError.batchOverAssigned) {
      try WeekPlan.apply(EntryChange(servings: .some(3)), to: edited, in: context)
    }
    #expect(edited.servings == 2 && other.servings == 2)
  }

  @Test func anUnreadableBatchDayCanBeRepairedByMovingItToAValidDay() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 2, in: context)
    let entry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
    entry.dayKey = ""
    #expect(WeekPlan.allocation(batch).hasInvalidEntries)
    try WeekPlan.apply(EntryChange(day: monday.adding(days: 1)), to: entry, in: context)
    #expect(entry.day == monday.adding(days: 1))
    #expect(!WeekPlan.allocation(batch).hasInvalidEntries)
  }

  @Test func anUnreadableDayCanBeExplicitlyRemovedWithoutUndoingToAnInventedDate() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 2, in: context)
    let entry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
    entry.dayKey = ""
    try WeekPlan.removeInvalid(entry, in: context)
    #expect(try context.fetchCount(FetchDescriptor<PlanEntryRecord>()) == 0)
    #expect(WeekPlan.assignedServings(batch) == 0)
    let valid = try WeekPlan.stirText("Valid", at: dinner(monday), into: context)
    #expect(throws: WeekPlanError.noDays) { try WeekPlan.removeInvalid(valid, in: context) }
  }

  @Test func undoRestoresBatchLinkAndRecipeEvenWhenBanished() throws {
    let context = try context()
    let soup = recipe("Soup", servings: 4, in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 3, in: context)
    let original = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
    let removed = try WeekPlan.remove(original, in: context)
    RecipeLibrary.banish(soup)
    let restored = try WeekPlan.restore(removed, in: context)
    #expect(restored.batch === batch && restored.recipe === soup)
    #expect(WeekPlan.assignedServings(batch) == 1)
    RecipeLibrary.restore(soup)
    #expect(restored.recipe === soup)
  }

  @Test func restoringBatchEntryRefusesUnavailableServingsWithoutAddingAnEntry() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 2, in: context)
    let original = try WeekPlan.assign(2, on: monday, slot: .dinner, to: batch, in: context)
    let removed = try WeekPlan.remove(original, in: context)
    _ = try WeekPlan.assign(2, on: monday.adding(days: 1), slot: .dinner, to: batch, in: context)
    #expect(throws: WeekPlanError.batchOverAssigned) { try WeekPlan.restore(removed, in: context) }
    #expect(try context.fetchCount(FetchDescriptor<PlanEntryRecord>()) == 1)
  }

  @Test func undoRefusesWhenItsBatchWasDeletedMeanwhile() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 2, in: context)
    let entry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
    let removed = try WeekPlan.remove(entry, in: context)
    WeekPlan.removeBatch(batch, in: context)
    #expect(throws: WeekPlanError.recipeMissing) { try WeekPlan.restore(removed, in: context) }
    #expect(try context.fetchCount(FetchDescriptor<PlanEntryRecord>()) == 0)
  }

  @Test func undoAfterRecipePurgeDoesNotResurrectDeletedRecipeReference() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 2, in: context)
    let entry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
    let removed = try WeekPlan.remove(entry, in: context)
    context.delete(soup)
    try context.save()
    let restored = try WeekPlan.restore(removed, in: context)
    #expect(restored.recipe == nil)
    #expect(restored.batch === batch)
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 0)
    #expect(WeekPlan.assignedServings(batch) == 1)
  }

  @Test func aFullMealRefusesTheWholeSpread() throws {
    let context = try context()
    let tuesday = monday.adding(days: 1)
    for n in 0..<WeekLimits.perSlot {
      try WeekPlan.stirText("Meal \(n)", at: dinner(tuesday), into: context)
    }
    #expect(throws: WeekPlanError.slotFull) {
      try WeekPlan.stir(
        recipe("Soup", in: context),
        days: [DayServings(date: monday, servings: 1), DayServings(date: tuesday, servings: 1)],
        slot: .dinner, into: context)
    }
    #expect(try titles(dinner(monday), in: context).isEmpty)
    #expect(try titles(dinner(tuesday), in: context).count == WeekLimits.perSlot)
  }

  @Test func aMealThatIsNotARecipeIsTrimmedAndNeedsAName() throws {
    let context = try context()
    let entry = try WeekPlan.stirText("  Leftovers \n", at: dinner(monday), into: context)
    #expect(entry.title == "Leftovers" && entry.recipe == nil && entry.servings == nil)
    #expect(throws: WeekPlanError.emptyTitle) {
      try WeekPlan.stirText("   ", at: dinner(monday), into: context)
    }
    #expect(throws: WeekPlanError.emptyTitle) {
      try WeekPlan.stirText(
        String(repeating: "x", count: WeekLimits.title + 1), at: dinner(monday), into: context)
    }
  }

  @Test func aMealTitleIsMeasuredInUTF16UnitsLikeTheWeb() throws {
    let context = try context()
    // An emoji is two units in JavaScript, so half the limit of them is the most that fits.
    let half = WeekLimits.title / 2
    let fits = String(repeating: "😀", count: half)
    let tooLong = String(repeating: "😀", count: half + 1)
    #expect(fits.count <= WeekLimits.title && tooLong.count <= WeekLimits.title)
    #expect(WeekLimits.fits(title: fits) && !WeekLimits.fits(title: tooLong))
    let entry = try WeekPlan.stirText(fits, at: dinner(monday), into: context)
    #expect(entry.title == fits)
    #expect(throws: WeekPlanError.emptyTitle) {
      try WeekPlan.stirText(tooLong, at: dinner(monday), into: context)
    }
    #expect(throws: WeekPlanError.emptyTitle) {
      try WeekPlan.apply(EntryChange(title: tooLong), to: entry, in: context)
    }
    #expect(entry.title == fits)
  }

  // MARK: Changing

  private func filled(_ context: ModelContext) throws -> [PlanEntryRecord] {
    try ["A", "B", "C"].map { try WeekPlan.stirText($0, at: dinner(monday), into: context) }
  }

  @Test func aMoveWithinAMealReorders() throws {
    let context = try context()
    let entries = try filled(context)
    try WeekPlan.apply(EntryChange(position: 0), to: entries[2], in: context)
    #expect(try titles(dinner(monday), in: context) == ["C", "A", "B"])
    #expect(try positions(dinner(monday), in: context) == [0, 1, 2])
  }

  @Test func aMoveToAnotherDayLandsAtTheEndAndClosesTheGap() throws {
    let context = try context()
    let entries = try filled(context)
    let tuesday = monday.adding(days: 1)
    try WeekPlan.stirText("Z", at: dinner(tuesday), into: context)
    try WeekPlan.apply(EntryChange(day: tuesday), to: entries[0], in: context)
    #expect(try titles(dinner(monday), in: context) == ["B", "C"])
    #expect(try positions(dinner(monday), in: context) == [0, 1])
    #expect(try titles(dinner(tuesday), in: context) == ["Z", "A"])
    #expect(entries[0].dayKey == "2026-10-06" && entries[0].position == 1)
  }

  @Test func aMoveToAnotherMealAtAPositionMakesRoom() throws {
    let context = try context()
    let entries = try filled(context)
    let lunch = MealTarget(day: monday, slot: .lunch)
    try WeekPlan.stirText("L", at: lunch, into: context)
    try WeekPlan.apply(EntryChange(slot: .lunch, position: 0), to: entries[1], in: context)
    #expect(try titles(lunch, in: context) == ["B", "L"])
    #expect(try titles(dinner(monday), in: context) == ["A", "C"])
    #expect(try positions(lunch, in: context) == [0, 1])
  }

  @Test func aMoveIntoAFullMealIsRefusedAndLeavesTheEntryWhereItWas() throws {
    let context = try context()
    let entries = try filled(context)
    let lunch = MealTarget(day: monday, slot: .lunch)
    for n in 0..<WeekLimits.perSlot { try WeekPlan.stirText("L\(n)", at: lunch, into: context) }
    #expect(throws: WeekPlanError.slotFull) {
      try WeekPlan.apply(EntryChange(slot: .lunch), to: entries[0], in: context)
    }
    #expect(entries[0].slot == .dinner)
    #expect(try titles(dinner(monday), in: context) == ["A", "B", "C"])
  }

  @Test func aPositionPastTheEndLandsLast() throws {
    let context = try context()
    let entries = try filled(context)
    try WeekPlan.apply(EntryChange(position: 99), to: entries[0], in: context)
    #expect(try titles(dinner(monday), in: context) == ["B", "C", "A"])
  }

  @Test func servingsChangeAndCanFollowTheRecipeAgain() throws {
    let context = try context()
    let entry = try WeekPlan.stir(
      recipe("Soup", in: context), days: [DayServings(date: monday, servings: 2)],
      slot: .dinner, into: context)[0]
    try WeekPlan.apply(EntryChange(servings: .some(6)), to: entry, in: context)
    #expect(entry.servings == 6)
    try WeekPlan.apply(EntryChange(servings: .some(nil)), to: entry, in: context)
    #expect(entry.servings == nil)
    #expect(throws: WeekPlanError.invalidServings) {
      try WeekPlan.apply(EntryChange(servings: .some(0)), to: entry, in: context)
    }
  }

  @Test func onlyFreeTextCanBeRenamed() throws {
    let context = try context()
    let text = try WeekPlan.stirText("Leftovers", at: dinner(monday), into: context)
    let soup = recipe("Soup", in: context)
    let entry = try WeekPlan.stir(
      soup, days: [DayServings(date: monday, servings: 1)], slot: .dinner, into: context)[0]
    try WeekPlan.apply(EntryChange(title: " Takeaway "), to: text, in: context)
    #expect(text.title == "Takeaway")
    try WeekPlan.apply(EntryChange(title: "Renamed"), to: entry, in: context)
    #expect(entry.title == "Soup")
    // Once its recipe is banished, an entry reads as free text and can be renamed.
    RecipeLibrary.banish(soup)
    try WeekPlan.apply(EntryChange(title: "Soup, from the freezer"), to: entry, in: context)
    #expect(entry.title == "Soup, from the freezer")
    #expect(throws: WeekPlanError.emptyTitle) {
      try WeekPlan.apply(EntryChange(title: "  "), to: text, in: context)
    }
  }

  @Test func aChangeThatChangesNothingLeavesEveryEntryUntouched() throws {
    let context = try context()
    let entries = try filled(context)
    try context.save()
    try WeekPlan.apply(EntryChange(position: 1), to: entries[1], in: context)
    #expect(context.changedModelsArray.isEmpty)
  }

  @Test func aChangeThatFailsPartwayIsRolledBackWhole() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let entry = try WeekPlan.stir(
      soup, days: [DayServings(date: monday, servings: 2)], slot: .dinner, into: context)[0]
    let lunch = MealTarget(day: monday, slot: .lunch)
    for n in 0..<WeekLimits.perSlot { try WeekPlan.stirText("L\(n)", at: lunch, into: context) }
    try context.save()
    #expect(throws: WeekPlanError.slotFull) {
      try WeekPlan.commit(in: context) {
        try WeekPlan.apply(
          EntryChange(slot: .lunch, servings: .some(5)), to: entry, in: context)
      }
    }
    #expect(entry.servings == 2 && entry.slot == .dinner)
    #expect(WeekPlan.message(for: WeekPlanError.slotFull).text == Copy.week.slotFull.text)
    #expect(WeekPlan.message(for: CocoaError(.fileWriteUnknown)).text == Copy.week.couldntSave.text)
  }

  // MARK: Removing

  @Test func removingClosesTheGap() throws {
    let context = try context()
    let entries = try filled(context)
    let removed = try WeekPlan.remove(entries[0], in: context)
    #expect(removed.title == "A" && removed.position == 0)
    #expect(try titles(dinner(monday), in: context) == ["B", "C"])
    #expect(try positions(dinner(monday), in: context) == [0, 1])
  }

  @Test func undoPutsARemovedEntryBackWhereItWas() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    try WeekPlan.stirText("A", at: dinner(monday), into: context)
    let middle = try WeekPlan.stir(
      soup, days: [DayServings(date: monday, servings: 3)], slot: .dinner, into: context)[0]
    try WeekPlan.stirText("C", at: dinner(monday), into: context)
    let removed = try WeekPlan.remove(middle, in: context)
    let back = try WeekPlan.restore(removed, in: context)
    #expect(try titles(dinner(monday), in: context) == ["A", "Soup", "C"])
    #expect(try positions(dinner(monday), in: context) == [0, 1, 2])
    #expect(back.recipe === soup && back.servings == 3)
  }

  @Test func undoAfterTheRecipeWasBanishedBringsBackTheTitleAlone() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let entry = try WeekPlan.stir(
      soup, days: [DayServings(date: monday, servings: 1)], slot: .dinner, into: context)[0]
    let removed = try WeekPlan.remove(entry, in: context)
    RecipeLibrary.banish(soup)
    let back = try WeekPlan.restore(removed, in: context)
    #expect(back.recipe == nil && back.title == "Soup")
  }

  // MARK: Dragging

  @Test func droppingOnAnotherEntryLandsBeforeIt() throws {
    let context = try context()
    let entries = try filled(context)
    let change = WeekPlan.dropMove(
      entries, moving: entries[2].id, to: dinner(monday), before: entries[0].id)
    #expect(change == EntryChange(day: monday, slot: .dinner, position: 0))
  }

  @Test func droppingOnAMealLandsAtTheEnd() throws {
    let context = try context()
    let entries = try filled(context)
    let lunch = MealTarget(day: monday, slot: .lunch)
    #expect(
      WeekPlan.dropMove(entries, moving: entries[0].id, to: lunch, before: nil)
        == EntryChange(day: monday, slot: .lunch, position: 0))
    #expect(
      WeekPlan.dropMove(entries, moving: entries[0].id, to: dinner(monday), before: nil)
        == EntryChange(day: monday, slot: .dinner, position: 2))
  }

  @Test func droppingWhereNothingWouldChangeDoesNothing() throws {
    let context = try context()
    let entries = try filled(context)
    // On itself, and the last entry dropped at the end of its own meal.
    #expect(
      WeekPlan.dropMove(
        entries, moving: entries[1].id, to: dinner(monday), before: entries[1].id) == nil)
    #expect(
      WeekPlan.dropMove(entries, moving: entries[2].id, to: dinner(monday), before: nil) == nil)
    #expect(
      WeekPlan.dropMove(entries, moving: UUID(), to: dinner(monday), before: nil) == nil)
  }

  // MARK: The whole week

  #if DEBUG
    private func seeded(today: String = "2026-10-11") throws -> ModelContext {
      let context = try context()
      try DebugSeed.populate(context, today: LocalDate(today)!)
      return context
    }

    @Test func copyingLastWeekCarriesEveryEntryForwardASevenDays() throws {
      let context = try seeded()
      let next = monday.adding(days: 7)
      #expect(try WeekPlan.copyLastWeek(into: next, in: context) == 5)
      let copied = try WeekPlan.fetch(from: next, through: next.adding(days: 6), in: context)
      let source = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
      #expect(copied.map(\.dayKey) == source.map { $0.day!.adding(days: 7).description })
      #expect(copied.map(\.title) == source.map(\.title))
      #expect(copied.map(\.servings) == source.map(\.servings))
      #expect(zip(copied, source).allSatisfy { $0.recipe === $1.recipe })
    }

    @Test func copyingAgainPlansItAllAgainAfterWhatIsThere() throws {
      let context = try seeded()
      let next = monday.adding(days: 7)
      try WeekPlan.copyLastWeek(into: next, in: context)
      try WeekPlan.copyLastWeek(into: next, in: context)
      let copied = try WeekPlan.fetch(from: next, through: next.adding(days: 6), in: context)
      #expect(copied.count == 10)
      #expect(copied.map(\.position).sorted() == [0, 0, 0, 0, 0, 1, 1, 1, 1, 1])
    }

    @Test func copyingFromAnEmptyWeekAddsNothing() throws {
      let context = try seeded()
      #expect(try WeekPlan.copyLastWeek(into: monday, in: context) == 0)
    }

    @Test func copyingStopsAtTheLimitOfAMeal() throws {
      let context = try context()
      let next = monday.adding(days: 7)
      for n in 0..<WeekLimits.perSlot {
        try WeekPlan.stirText("Held \(n)", at: dinner(next), into: context)
      }
      try WeekPlan.stirText("Last week's", at: dinner(monday), into: context)
      #expect(try WeekPlan.copyLastWeek(into: next, in: context) == 0)
      #expect(try titles(dinner(next), in: context).count == WeekLimits.perSlot)
    }

    @Test func copyingKeepsBatchIdentitySeparateAndCopiesEmptyBatches() throws {
      let context = try context()
      let soup = recipe("Soup", in: context)
      let batch = try WeekPlan.createBatch(
        recipe: soup, weekStart: monday, totalServings: 3, in: context)
      let entry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
      try context.save()
      let next = monday.adding(days: 7)
      #expect(try WeekPlan.copyLastWeek(into: next, in: context) == 1)
      let batches = try WeekPlan.batches(from: next, through: next.adding(days: 6), in: context)
      #expect(batches.count == 1 && batches[0] !== batch)
      #expect(batches[0].totalServings == 3 && WeekPlan.unassignedServings(batches[0]) == 2)
      let copied = try WeekPlan.fetch(from: next, through: next.adding(days: 6), in: context)
      #expect(copied.count == 1 && copied[0].batch === batches[0] && copied[0].id != entry.id)
    }

    @Test func copyingAZeroAssignmentBatchReportsSuccess() throws {
      let context = try context()
      let soup = recipe("Soup", in: context)
      _ = try WeekPlan.createBatch(recipe: soup, weekStart: monday, totalServings: 3, in: context)
      let next = monday.adding(days: 7)
      #expect(try WeekPlan.copyLastWeek(into: next, in: context) == 1)
      let copies = try WeekPlan.batches(from: next, through: next.adding(days: 6), in: context)
      #expect(copies.count == 1 && WeekPlan.assignedServings(copies[0]) == 0)
    }

    @Test func copyDiscoversAssignmentLinkedBatchWhoseStoredRangeStartsOutsideSourceWeek() throws {
      let context = try context()
      let soup = recipe("Soup", servings: nil, in: context)
      let sourceStart = monday.adding(days: -1)
      let batch = PlannedBatchRecord(
        weekStart: sourceStart, title: soup.title, totalServings: 4, ingredientYield: 4)
      batch.recipe = soup
      context.insert(batch)
      let sourceEntry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
      let next = monday.adding(days: 7)

      #expect(try WeekPlan.copyLastWeek(into: next, in: context) == 1)
      let copiedBatch = try #require(
        try WeekPlan.batches(
          from: next.adding(days: -1), through: next.adding(days: 5), in: context
        )
        .first { $0.id != batch.id })
      let copiedEntry = try #require(
        try WeekPlan.fetch(from: next, through: next.adding(days: 6), in: context)
          .first { $0.id != sourceEntry.id })
      #expect(copiedEntry.batch === copiedBatch)
      #expect(copiedBatch.weekStartKey == "2026-10-11")
      #expect(copiedBatch.ingredientYield == 4)
    }

    @Test func copyRefusesMalformedLinkedBatchRangeInsteadOfDroppingItsGrouping() throws {
      let context = try context()
      let soup = recipe("Soup", in: context)
      let batch = try WeekPlan.createBatch(
        recipe: soup, weekStart: monday, totalServings: 2, in: context)
      let entry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
      batch.weekStartKey = "not-a-date"
      let next = monday.adding(days: 7)
      #expect(throws: WeekPlanError.noDays) { try WeekPlan.copyLastWeek(into: next, in: context) }
      #expect(try WeekPlan.fetch(from: next, through: next.adding(days: 6), in: context).isEmpty)
      #expect(entry.batch === batch)
    }

    @Test func clearingOnlyDeletesBatchesWhoseFullRangeWasCleared() throws {
      let context = try context()
      let soup = recipe("Soup", in: context)
      let batch = try WeekPlan.createBatch(
        recipe: soup, weekStart: monday, totalServings: 2, in: context)
      let entry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
      #expect(
        try WeekPlan.clear(
          from: monday.adding(days: 1), through: monday.adding(days: 5), in: context) == 0)
      #expect(try WeekPlan.batches(from: monday, through: monday, in: context).first === batch)
      #expect(entry.batch === batch)
      #expect(try WeekPlan.clear(week: monday, in: context) == 1)
      #expect(try WeekPlan.batches(from: monday, through: monday, in: context).isEmpty)
    }

    @Test func clearingWeekNeverCascadesIntoLinkedAssignmentOutsideRange() throws {
      let context = try context()
      let soup = recipe("Soup", in: context)
      let batch = try WeekPlan.createBatch(
        recipe: soup, weekStart: monday, totalServings: 2, in: context)
      let entry = try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
      entry.day = monday.adding(days: 7)
      #expect(try WeekPlan.clear(week: monday, in: context) == 0)
      #expect(entry.modelContext === context)
      #expect(entry.day == monday.adding(days: 7))
      #expect(try WeekPlan.batches(from: monday, through: monday, in: context).first === batch)
      #expect(entry.batch === batch)
    }

    @Test func clearingTheWeekLeavesOtherWeeksAlone() throws {
      let context = try seeded()
      try WeekPlan.copyLastWeek(into: monday.adding(days: 7), in: context)
      #expect(try WeekPlan.clear(week: monday, in: context) == 5)
      #expect(
        try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context).isEmpty)
      #expect(
        try WeekPlan.fetch(
          from: monday.adding(days: 7), through: monday.adding(days: 13), in: context
        ).count == 5)
    }

    // MARK: Tallies, against the web app

    // The numbers below come from the TypeScript rules (`tallyMacros` in
    // `packages/shared/src/planMacros.ts`) applied by hand to the seed's per-serving macros
    // (`packages/db/src/seed-recipes.ts`) and its planned week, not from this code, so they
    // fail if the port drifts. Monday chicken x4, Tuesday soup x4, Wednesday shakshuka x4,
    // Thursday oats x2, Saturday cookies x12 (the cookies have no macros).
    @Test func theSeededWeekTalliesAsTheWebAppDoes() throws {
      let context = try seeded()
      let records = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
      let snapshot = WeekSnapshot(start: monday, records: records)
      #expect(snapshot.meals.count == 5)
      #expect(
        snapshot.weekTally.totals == MacroTotals(calories: 4720, protein: 280, carbs: 364, fat: 236)
      )
      #expect(snapshot.weekTally.counted == 4 && snapshot.weekTally.missing == 1)
      #expect(snapshot.daysPlanned == 4)
      #expect(
        WeekFigures.average(of: snapshot.weekTally, daysPlanned: 4, locale: en)
          == "≈ 1,180 kcal a day")

      let perDay: [(offset: Int, totals: MacroTotals)] = [
        (0, MacroTotals(calories: 1680, protein: 136, carbs: 24, fat: 112)),
        (1, MacroTotals(calories: 1040, protein: 48, carbs: 152, fat: 28)),
        (2, MacroTotals(calories: 1240, protein: 68, carbs: 72, fat: 76)),
        (3, MacroTotals(calories: 760, protein: 28, carbs: 116, fat: 20)),
        (4, .zero),
        (5, .zero),
        (6, .zero),
      ]
      for (offset, totals) in perDay {
        #expect(snapshot.tally(of: monday.adding(days: offset)).totals == totals, "day \(offset)")
      }
      let saturday = snapshot.tally(of: monday.adding(days: 5))
      #expect(saturday.missing == 1 && saturday.counted == 0)
    }

    @Test func theSeededWeekSaysWhatTheWebAppSaysOfItsGaps() throws {
      let context = try seeded()
      let records = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
      let snapshot = WeekSnapshot(start: monday, records: records)
      #expect(
        WeekFigures.note(week: snapshot.weekTally, day: nil)
          == "1 planned meal isn't fully counted.")
      #expect(
        WeekFigures.note(week: snapshot.weekTally, day: snapshot.tally(of: monday))
          == "1 planned meal isn't fully counted.")
    }

    @Test func anEmptyWeekAsksForRecipesWithMacros() {
      let snapshot = WeekSnapshot(start: monday, records: [])
      #expect(snapshot.isEmpty)
      #expect(
        WeekFigures.note(week: snapshot.weekTally, day: nil)
          == "Add calories and macros to your recipes to see totals here.")
    }

    @Test func aMealCardSaysTimeServingsAndCalories() throws {
      let context = try seeded()
      let records = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
      let monday = try #require(WeekSnapshot(start: monday, records: records).meals.first)
      let card = MealCard(monday)
      #expect(card.title.hasPrefix("Weeknight chicken"))
      #expect(card.detail == "\(formatTimer(55 * 60)) · 4 servings · 1,680 kcal")
      #expect(card.isRecipe)
    }
  #endif

  // MARK: Reading

  @Test func aBanishedRecipeKeepsItsEntryAsAMealWithNothingToCount() throws {
    let context = try context()
    let soup = recipe(
      "Soup", macros: Macros(calories: 100, protein: 1, carbs: 2, fat: 3), in: context)
    let entry = try WeekPlan.stir(
      soup, days: [DayServings(date: monday, servings: 2)], slot: .dinner, into: context)[0]
    #expect(WeekPlan.meal(entry)?.recipe?.title == "Soup")
    RecipeLibrary.banish(soup)
    let meal = try #require(WeekPlan.meal(entry))
    #expect(meal.recipe == nil && meal.title == "Soup")
    let snapshot = WeekSnapshot(start: monday, records: [entry])
    #expect(snapshot.weekTally.freeText == 1)
    #expect(snapshot.weekTally.totals == .zero)
    #expect(MealCard(meal).detail == nil && !MealCard(meal).isRecipe)
  }

  @Test func weeklySnapshotUsesSavedManualTargetsAndReflectsEdits() throws {
    let context = try context()
    let targets = TargetsRecord(calories: 2_000, protein: 100, carbs: 200, fat: 70)
    targets.caloriesOverridden = true
    targets.proteinOverridden = true
    context.insert(targets)
    #expect(targets.caloriesOverridden && targets.proteinOverridden)
    let recipe = recipe(
      "Soup", servings: 1, macros: Macros(calories: 500, protein: 25, carbs: 40, fat: 10),
      in: context)
    try WeekPlan.stir(recipe, at: dinner(monday), servings: 1, into: context)

    let first = WeekSnapshot(
      start: monday,
      records: try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context),
      targets: targets)
    #expect(first.weekTally.totals.calories == 500)
    #expect(first.weeklyComparison?.target.calories == 14_000)
    #expect(first.weeklyComparison?.target.protein == 700)
    #expect(first.weeklyComparison?.target.carbs == 1_400)
    #expect(first.weeklyComparison?.target.fat == 490)
    #expect(first.weeklyComparison?.remaining(for: .calories) == 13_500)
    #expect(first.tally(of: monday).totals.calories == 500)
    targets.calories = 100
    let changed = WeekSnapshot(
      start: monday,
      records: try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context),
      targets: targets)
    #expect(changed.weeklyComparison?.target.calories == 700)
    #expect(changed.weeklyComparison?.remaining(for: .calories) == 200)
    #expect(WeekSnapshot(start: monday, records: []).weeklyComparison == nil)
    let emptyWithTargets = WeekSnapshot(start: monday, records: [], targets: targets)
    #expect(emptyWithTargets.weekTally.totals.calories == 0)
    #expect(emptyWithTargets.weeklyComparison?.target.calories == 700)
    #expect(emptyWithTargets.weeklyComparison?.remaining(for: .calories) == 700)
  }

  @Test func weeklyComparisonPreservesFractionalProteinDifferencesInItsPresentedRow() throws {
    func row(lastServingProtein: Double) throws -> (Double, String) {
      let context = try context()
      let target = TargetsRecord(calories: 2_000, protein: 100, carbs: 200, fat: 70)
      context.insert(target)
      let usual = recipe(
        "Protein meal", servings: 1,
        macros: Macros(calories: 100, protein: 100, carbs: 10, fat: 5), in: context)
      let last = recipe(
        "Last protein meal", servings: 1,
        macros: Macros(calories: 100, protein: lastServingProtein, carbs: 10, fat: 5),
        in: context)
      let days = monday.weekDays()
      try WeekPlan.stir(
        usual, days: days.prefix(6).map { DayServings(date: $0, servings: 1) }, slot: .dinner,
        into: context)
      try WeekPlan.stir(last, at: dinner(days[6]), servings: 1, into: context)
      let records = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
      let snapshot = WeekSnapshot(start: monday, records: records, targets: target)
      let comparison = try #require(snapshot.weeklyComparison)
      return (
        comparison.planned.protein,
        WeekFigures.comparisonRow(comparison, key: .protein, locale: en)
      )
    }

    let below = try row(lastServingProtein: 99.5)
    #expect(below.0 == 699.5)
    #expect(below.1 == "Protein: 699.5 g planned, 700 g target, 0.5 g remaining")
    let exact = try row(lastServingProtein: 100)
    #expect(exact.0 == 700)
    #expect(exact.1 == "Protein: 700 g planned, 700 g target, 0 g remaining")
    let above = try row(lastServingProtein: 100.1)
    #expect(above.0 == 700.1)
    #expect(above.1 == "Protein: 700.1 g planned, 700 g target, 0.1 g over target")
    let belowPrecision = try row(lastServingProtein: 100.04)
    #expect(belowPrecision.0 == 700.04)
    #expect(belowPrecision.1 == "Protein: 700 g planned, 700 g target, <0.1 g over target")
  }

  @Test func compactWeeklyPairAndAccessibilityRetainSmallOverGoalDifference() {
    func comparison(protein: Double, counted: Int) -> WeekMacroComparison {
      let tally = MacroTally(
        totals: MacroTotals(calories: 0, protein: protein, carbs: 0, fat: 0),
        counted: counted, missing: 0, freeText: 0)
      return WeekMacroComparison(
        tally: tally, dailyTarget: MacroTargets(calories: 0, protein: 100, carbs: 0, fat: 0))
    }

    let roundoff = comparison(
      protein: (0..<7).reduce(0) { $0 + 100.00000000000001 }, counted: 7)
    #expect(roundoff.planned.protein > roundoff.target.protein)
    #expect(roundoff.remaining(for: .protein) == 0)
    #expect(!WeekFigures.isOverGoal(roundoff, key: .protein))
    let roundedPair = Copy.week.tally.compactMetric(
      name: "Protein", planned: WeekFigures.compactAmount(roundoff.planned.protein, locale: en),
      goal: WeekFigures.compactAmount(roundoff.target.protein, locale: en), unit: "g",
      isOver: WeekFigures.isOverGoal(roundoff, key: .protein))
    #expect(roundedPair.text == "Protein: Planned 700 / Goal 700 g")

    let tinyOverage = comparison(protein: 700.004, counted: 7)
    let tinyPlanned = WeekFigures.compactAmount(tinyOverage.planned.protein, locale: en)
    let tinyGoal = WeekFigures.compactAmount(tinyOverage.target.protein, locale: en)
    #expect(tinyPlanned == tinyGoal)
    #expect(WeekFigures.isOverGoal(tinyOverage, key: .protein))
    #expect(
      Copy.week.tally.compactMetric(
        name: "Protein", planned: tinyPlanned, goal: tinyGoal, unit: "g",
        isOver: WeekFigures.isOverGoal(tinyOverage, key: .protein)
      ).text == "Protein: Planned 700 / Goal 700 g, over goal")

    let actualOverage = comparison(protein: 700.04, counted: 7)
    let planned = WeekFigures.compactAmount(actualOverage.planned.protein, locale: en)
    let goal = WeekFigures.compactAmount(actualOverage.target.protein, locale: en)
    #expect(planned == "700.04")
    #expect(planned != goal)
    #expect(
      Copy.week.tally.compactMetric(
        name: "Protein", planned: planned, goal: goal, unit: "g",
        isOver: WeekFigures.isOverGoal(actualOverage, key: .protein)
      ).text == "Protein: Planned 700.04 / Goal 700 g, over goal")
  }

  @Test func snapshotComparisonMatrixCoversEveryMetricAndPeriodBoundary() throws {
    struct MetricCase {
      let key: MacroKey
      let dailyGoal: Double
      let dailyRows: [String]
      let weeklyRows: [String]
    }
    let metrics = [
      MetricCase(
        key: .calories, dailyGoal: 2_000,
        dailyRows: [
          "Calories: 1,999.5 kcal planned, 2,000 kcal target, 0.5 kcal remaining",
          "Calories: 2,000 kcal planned, 2,000 kcal target, <0.1 kcal remaining",
          "Calories: 2,000 kcal planned, 2,000 kcal target, 0 kcal remaining",
          "Calories: 2,000 kcal planned, 2,000 kcal target, 0 kcal remaining",
          "Calories: 2,000 kcal planned, 2,000 kcal target, 0 kcal remaining",
          "Calories: 2,000 kcal planned, 2,000 kcal target, <0.1 kcal over target",
          "Calories: 2,000.5 kcal planned, 2,000 kcal target, 0.5 kcal over target",
        ],
        weeklyRows: [
          "Calories: 13,999.5 kcal planned, 14,000 kcal target, 0.5 kcal remaining",
          "Calories: 14,000 kcal planned, 14,000 kcal target, <0.1 kcal remaining",
          "Calories: 14,000 kcal planned, 14,000 kcal target, 0 kcal remaining",
          "Calories: 14,000 kcal planned, 14,000 kcal target, 0 kcal remaining",
          "Calories: 14,000 kcal planned, 14,000 kcal target, 0 kcal remaining",
          "Calories: 14,000 kcal planned, 14,000 kcal target, <0.1 kcal over target",
          "Calories: 14,000.5 kcal planned, 14,000 kcal target, 0.5 kcal over target",
        ]),
      MetricCase(
        key: .protein, dailyGoal: 100,
        dailyRows: [
          "Protein: 99.5 g planned, 100 g target, 0.5 g remaining",
          "Protein: 100 g planned, 100 g target, <0.1 g remaining",
          "Protein: 100 g planned, 100 g target, 0 g remaining",
          "Protein: 100 g planned, 100 g target, 0 g remaining",
          "Protein: 100 g planned, 100 g target, 0 g remaining",
          "Protein: 100 g planned, 100 g target, <0.1 g over target",
          "Protein: 100.5 g planned, 100 g target, 0.5 g over target",
        ],
        weeklyRows: [
          "Protein: 699.5 g planned, 700 g target, 0.5 g remaining",
          "Protein: 700 g planned, 700 g target, <0.1 g remaining",
          "Protein: 700 g planned, 700 g target, 0 g remaining",
          "Protein: 700 g planned, 700 g target, 0 g remaining",
          "Protein: 700 g planned, 700 g target, 0 g remaining",
          "Protein: 700 g planned, 700 g target, <0.1 g over target",
          "Protein: 700.5 g planned, 700 g target, 0.5 g over target",
        ]),
      MetricCase(
        key: .carbs, dailyGoal: 200,
        dailyRows: [
          "Carbs: 199.5 g planned, 200 g target, 0.5 g remaining",
          "Carbs: 200 g planned, 200 g target, <0.1 g remaining",
          "Carbs: 200 g planned, 200 g target, 0 g remaining",
          "Carbs: 200 g planned, 200 g target, 0 g remaining",
          "Carbs: 200 g planned, 200 g target, 0 g remaining",
          "Carbs: 200 g planned, 200 g target, <0.1 g over target",
          "Carbs: 200.5 g planned, 200 g target, 0.5 g over target",
        ],
        weeklyRows: [
          "Carbs: 1,399.5 g planned, 1,400 g target, 0.5 g remaining",
          "Carbs: 1,400 g planned, 1,400 g target, <0.1 g remaining",
          "Carbs: 1,400 g planned, 1,400 g target, 0 g remaining",
          "Carbs: 1,400 g planned, 1,400 g target, 0 g remaining",
          "Carbs: 1,400 g planned, 1,400 g target, 0 g remaining",
          "Carbs: 1,400 g planned, 1,400 g target, <0.1 g over target",
          "Carbs: 1,400.5 g planned, 1,400 g target, 0.5 g over target",
        ]),
      MetricCase(
        key: .fat, dailyGoal: 70,
        dailyRows: [
          "Fat: 69.5 g planned, 70 g target, 0.5 g remaining",
          "Fat: 70 g planned, 70 g target, <0.1 g remaining",
          "Fat: 70 g planned, 70 g target, 0 g remaining",
          "Fat: 70 g planned, 70 g target, 0 g remaining",
          "Fat: 70 g planned, 70 g target, 0 g remaining",
          "Fat: 70 g planned, 70 g target, <0.1 g over target",
          "Fat: 70.5 g planned, 70 g target, 0.5 g over target",
        ],
        weeklyRows: [
          "Fat: 489.5 g planned, 490 g target, 0.5 g remaining",
          "Fat: 490 g planned, 490 g target, <0.1 g remaining",
          "Fat: 490 g planned, 490 g target, 0 g remaining",
          "Fat: 490 g planned, 490 g target, 0 g remaining",
          "Fat: 490 g planned, 490 g target, 0 g remaining",
          "Fat: 490 g planned, 490 g target, <0.1 g over target",
          "Fat: 490.5 g planned, 490 g target, 0.5 g over target",
        ]),
    ]

    for metric in metrics {
      for days in [1, 7] {
        let goal = metric.dailyGoal * Double(days)
        let expectedRows = days == 1 ? metric.dailyRows : metric.weeklyRows
        for (scenario, delta) in [-0.5, -0.0000001, -goal.ulp, 0.0, goal.ulp, 0.0000001, 0.5]
          .enumerated()
        {
          let context = try context()
          let target = TargetsRecord(calories: 2_000, protein: 100, carbs: 200, fat: 70)
          context.insert(target)
          var values = Dictionary(
            uniqueKeysWithValues: metrics.map { ($0.key, $0.dailyGoal * Double(days) - 0.08) })
          values[metric.key] = goal + delta - 0.08
          let components = [
            values, Dictionary(uniqueKeysWithValues: metrics.map { ($0.key, 0.04) }),
            Dictionary(uniqueKeysWithValues: metrics.map { ($0.key, 0.04) }),
          ]
          for (index, component) in components.enumerated() {
            let item = recipe(
              "Fractional meal \(index + 1)", servings: 1,
              macros: Macros(
                calories: component[.calories], protein: component[.protein],
                carbs: component[.carbs], fat: component[.fat]), in: context)
            try WeekPlan.stir(item, at: dinner(monday), servings: 1, into: context)
          }
          let records = try WeekPlan.fetch(
            from: monday, through: monday.adding(days: 6), in: context)
          let snapshot = WeekSnapshot(start: monday, records: records, targets: target)
          let comparison = try #require(
            days == 1 ? snapshot.dailyComparison(for: monday) : snapshot.weeklyComparison)
          let row = WeekFigures.comparisonRow(comparison, key: metric.key, locale: en)
          #expect(row == expectedRows[scenario])
        }
      }
    }
  }

  @Test func weeklyComparisonKeepsFullDenominatorAndQualifiesPartialAndFreeTextMeals() throws {
    let context = try context()
    let targets = TargetsRecord(calories: 2_000, protein: 100, carbs: 200, fat: 70)
    context.insert(targets)
    let soup = recipe("Partial soup", servings: 1, macros: Macros(calories: 500), in: context)
    try WeekPlan.stir(soup, at: dinner(monday.adding(days: 3)), servings: 1, into: context)
    try WeekPlan.stirText("Takeaway", at: dinner(monday.adding(days: 4)), into: context)
    let records = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
    let snapshot = WeekSnapshot(start: monday, records: records, targets: targets)
    #expect(snapshot.weeklyComparison?.target.calories == 14_000)
    #expect(snapshot.weeklyComparison?.isIncomplete == true)
    #expect(snapshot.weekTally.missing == 1 && snapshot.weekTally.freeText == 1)
    #expect(WeekFigures.note(week: snapshot.weekTally, day: snapshot.tally(of: monday)) != nil)
  }

  @Test func selectedDayComparesAgainstOneDayTargetsWithIndependentCompleteness() throws {
    let context = try context()
    let targets = TargetsRecord(calories: 2_000, protein: 100, carbs: 200, fat: 70)
    context.insert(targets)
    let counted = recipe(
      "Counted", servings: 1, macros: Macros(calories: 1_600, protein: 99.5, carbs: 200, fat: 70),
      in: context)
    let partial = recipe("Partial", servings: 1, macros: Macros(calories: 100), in: context)
    try WeekPlan.stir(counted, at: dinner(monday), servings: 1, into: context)
    try WeekPlan.stir(partial, at: dinner(monday.adding(days: 1)), servings: 1, into: context)
    try WeekPlan.stirText("Takeaway", at: dinner(monday.adding(days: 2)), into: context)
    let records = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
    let snapshot = WeekSnapshot(start: monday, records: records, targets: targets)
    let comparison = try #require(snapshot.dailyComparison(for: monday))
    #expect(comparison.planned.calories == 1_600)
    #expect(comparison.target.calories == 2_000)
    #expect(comparison.remaining(for: .calories) == 400)
    #expect(comparison.planned.protein == 99.5)
    #expect(
      WeekFigures.comparisonRow(comparison, key: .protein, locale: en)
        == "Protein: 99.5 g planned, 100 g target, 0.5 g remaining")
    #expect(!comparison.isIncomplete)
    #expect(snapshot.weeklyComparison?.isIncomplete == true)
    #expect(
      WeekFigures.note(week: snapshot.weekTally, day: snapshot.tally(of: monday))
        == Copy.week.tally.gaps(2).text)
    #expect(WeekFigures.note(week: snapshot.tally(of: monday), day: nil) == nil)
    let empty = try #require(snapshot.dailyComparison(for: monday.adding(days: 3)))
    #expect(empty.planned.calories == 0 && empty.target.calories == 2_000)
    #expect(empty.remaining(for: .calories) == 2_000)
    #expect(snapshot.dailyComparison(for: monday.adding(days: 1))?.isIncomplete == true)
    #expect(WeekSnapshot(start: monday, records: []).dailyComparison(for: monday) == nil)
  }

  @Test func movingAnAssignmentIntoAViewedRangeUpdatesNutritionWithoutChangingAllocation() throws {
    let context = try context()
    let soup = recipe("Soup", servings: 2, macros: Macros(calories: 500), in: context)
    let batch = try WeekPlan.createBatch(
      recipe: soup, weekStart: monday, totalServings: 2, in: context)
    let outsideDisplayedWeek = try WeekPlan.assign(
      1, on: monday.adding(days: 6), slot: .dinner, to: batch, in: context)
    let displayedSunday = monday.adding(days: -1)

    let before = try WeekSnapshot(
      start: displayedSunday,
      records: WeekPlan.fetch(
        from: displayedSunday, through: displayedSunday.adding(days: 6), in: context))
    let allocationBefore = WeekPlan.allocation(batch)
    #expect(before.weekTally.totals.calories == 0)
    #expect(allocationBefore.assigned == 1 && allocationBefore.unassigned == 1)

    try WeekPlan.apply(
      EntryChange(day: displayedSunday.adding(days: 6)), to: outsideDisplayedWeek, in: context)
    let after = try WeekSnapshot(
      start: displayedSunday,
      records: WeekPlan.fetch(
        from: displayedSunday, through: displayedSunday.adding(days: 6), in: context))
    let allocationAfter = WeekPlan.allocation(batch)
    #expect(after.weekTally.totals.calories == 500)
    #expect(allocationAfter.assigned == allocationBefore.assigned)
    #expect(allocationAfter.unassigned == allocationBefore.unassigned)
  }

  @Test func selectedDayTreatsSummedDecimalServingsAsExactWhenOnlyRoundoffDiffers() throws {
    let context = try context()
    let targets = TargetsRecord(calories: 2_000, protein: 333, carbs: 200, fat: 70)
    context.insert(targets)
    let meal = recipe(
      "Decimal protein", servings: 1,
      macros: Macros(calories: 100, protein: 33.3, carbs: 20, fat: 5), in: context)
    for _ in 0..<10 {
      try WeekPlan.stir(meal, at: dinner(monday), servings: 1, into: context)
    }
    let records = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
    let comparison = try #require(
      WeekSnapshot(start: monday, records: records, targets: targets).dailyComparison(for: monday))
    #expect(comparison.planned.protein == 333.00000000000006)
    #expect(comparison.remaining(for: .protein) == 0)
    #expect(
      WeekFigures.comparisonRow(comparison, key: .protein, locale: en)
        == "Protein: 333 g planned, 333 g target, 0 g remaining")
    let slightlyOver = recipe(
      "Slightly over", servings: 1,
      macros: Macros(calories: 100, protein: 33.30000001, carbs: 20, fat: 5), in: context)
    for _ in 0..<10 {
      try WeekPlan.stir(
        slightlyOver, at: dinner(monday.adding(days: 1)), servings: 1, into: context)
    }
    let updatedRecords = try WeekPlan.fetch(
      from: monday, through: monday.adding(days: 6), in: context)
    let slightlyOverComparison = try #require(
      WeekSnapshot(start: monday, records: updatedRecords, targets: targets)
        .dailyComparison(for: monday.adding(days: 1)))
    #expect(slightlyOverComparison.remaining(for: .protein) < -0.00000005)
  }

  @Test func plannedBatchCapacityDoesNotChangeTallyButAssignmentsDo() throws {
    let context = try context()
    let recipe = recipe(
      "Batch", servings: 4, macros: Macros(calories: 500, protein: 20, carbs: 50, fat: 10),
      in: context)
    let batch = try WeekPlan.createBatch(
      recipe: recipe, weekStart: monday, totalServings: 4, in: context)
    try WeekPlan.assign(1, on: monday, slot: .dinner, to: batch, in: context)
    func calories() throws -> Double {
      let records = try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context)
      return WeekSnapshot(start: monday, records: records).weekTally.totals.calories
    }
    #expect(try calories() == 500)
    try WeekPlan.editTotal(batch, to: 6)
    #expect(try calories() == 500)
    try WeekPlan.assign(1, on: monday.adding(days: 1), slot: .dinner, to: batch, in: context)
    #expect(try calories() == 1_000)
  }

  @Test func anEntryIsBrewedWhenItsRecipeWasCookedThatDay() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let entry = try WeekPlan.stir(
      soup, days: [DayServings(date: monday, servings: 1)], slot: .dinner, into: context)[0]
    #expect(WeekPlan.meal(entry)?.brewed == false)
    let cook = CookRecord(cookedOn: monday.adding(days: 1))
    context.insert(cook)
    cook.recipe = soup
    #expect(WeekPlan.meal(entry)?.brewed == false)
    let cooked = CookRecord(cookedOn: monday)
    context.insert(cooked)
    cooked.recipe = soup
    let meal = try #require(WeekPlan.meal(entry))
    #expect(meal.brewed)
    #expect(MealCard(meal).detail == Copy.week.brewed.text)
  }

  @Test func theWeekOnlyShowsItsOwnDaysInOrder() throws {
    let context = try context()
    try WeekPlan.stirText(
      "Late", at: MealTarget(day: monday.adding(days: 6), slot: .snack), into: context)
    try WeekPlan.stirText("Next week", at: dinner(monday.adding(days: 7)), into: context)
    try WeekPlan.stirText("Dinner", at: dinner(monday), into: context)
    try WeekPlan.stirText("Breakfast", at: MealTarget(day: monday, slot: .breakfast), into: context)
    let all = try context.fetch(FetchDescriptor<PlanEntryRecord>())
    let snapshot = WeekSnapshot(start: monday, records: all)
    #expect(snapshot.meals.map(\.title) == ["Breakfast", "Dinner", "Late"])
    #expect(snapshot.meals(on: monday, slot: .dinner).map(\.title) == ["Dinner"])
    #expect(
      try WeekPlan.fetch(from: monday, through: monday.adding(days: 6), in: context).count == 3)
  }

  @Test func anEntryWithAnUnreadableDayIsLeftOut() throws {
    let context = try context()
    let entry = try WeekPlan.stirText("Odd", at: dinner(monday), into: context)
    entry.dayKey = "someday"
    #expect(WeekPlan.meal(entry) == nil)
  }

  // MARK: The recipe page

  @Test func theRecipePageOffersTwoWeeksFromToday() {
    let days = WeekPlan.upcoming(from: monday)
    #expect(days.count == 14)
    #expect(days.first == monday && days.last == monday.adding(days: 13))
  }

  @Test func theChosenScaleBecomesTheEntrysServings() {
    #expect(WeekPlan.servings(for: .servings(6), recipeServings: 4) == 6)
    #expect(WeekPlan.servings(for: .servings(4), recipeServings: 4) == nil)
    #expect(WeekPlan.servings(for: .servings(3), recipeServings: nil) == 3)
    #expect(WeekPlan.servings(for: .multiplier(2), recipeServings: 4) == nil)
    #expect(WeekPlan.servings(for: .servings(WeekLimits.servings + 1), recipeServings: 4) == nil)
  }
}
