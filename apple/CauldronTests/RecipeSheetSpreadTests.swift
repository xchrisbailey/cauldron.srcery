import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

/// The recipe page's "Stir into the week": the spread it opens with, what changing the
/// starting day does, and what writing several days in one go does.
@MainActor
@Suite("Recipe page spread")
struct RecipeSheetSpreadTests {
  /// A Wednesday.
  private let today = LocalDate("2026-10-14")!

  private func context() throws -> ModelContext {
    ModelContext(try CauldronStore.container(.inMemory))
  }

  private func recipe(
    _ title: String = "Chili", servings: Int? = 5, in context: ModelContext
  ) -> RecipeRecord {
    let record = RecipeRecord(title: title)
    record.servings = servings
    context.insert(record)
    return record
  }

  private func opening(_ recipe: RecipeRecord, scale: Scale? = nil) -> SpreadPlan {
    StirRecipeSheet.startingPlan(
      recipe: recipe, scale: scale ?? .initial(servings: recipe.servings), today: today)
  }

  private func everything(_ context: ModelContext) throws -> [PlanEntryRecord] {
    WeekPlan.ordered(try context.fetch(FetchDescriptor<PlanEntryRecord>()))
  }

  // MARK: The default spread

  @Test func aFiveServingRecipeLandsInFiveDaysOneServingEach() throws {
    let context = try context()
    let plan = opening(recipe(servings: 5, in: context))
    #expect(plan.slot == .dinner)
    #expect(plan.anchor == today)
    #expect(
      plan.entries == (0..<5).map { DayServings(date: today.adding(days: $0), servings: 1) })
    #expect(plan.summary == "5 of 5 servings planned")
    #expect(!plan.isOver)
  }

  @Test func theSpreadCoversTheSevenDaysFromTheStartingDayNotTheCalendarWeek() throws {
    let context = try context()
    let plan = opening(recipe(servings: 5, in: context))
    #expect(plan.days == today.startOfWeek().weekDays())
    #expect(plan.picked.last == today.adding(days: 4))
    #expect(plan.days.first == LocalDate("2026-10-12")!)
    #expect(plan.days.last == today.adding(days: 4))
  }

  @Test func aBatchBiggerThanTheWindowFillsTheSevenDays() throws {
    let context = try context()
    let plan = opening(recipe(servings: 12, in: context))
    #expect(plan.picked.count == 5)
    #expect(plan.planned == 5)
    #expect(plan.summary == "5 of 12 servings planned")
  }

  @Test func aOneServingRecipeStartsOnTheStartingDayOnly() throws {
    let context = try context()
    let plan = opening(recipe(servings: 1, in: context))
    #expect(plan.entries == [DayServings(date: today, servings: 1)])
  }

  @Test func aRecipeWithNoServingsStartsOnTheStartingDayOnly() throws {
    let context = try context()
    let plan = opening(recipe(servings: nil, in: context))
    #expect(plan.entries == [DayServings(date: today, servings: 1)])
    #expect(plan.summary == "1 serving planned")
  }

  @Test func aScaledRecipeSpreadsTheScaledTotal() throws {
    let context = try context()
    let chili = recipe(servings: 5, in: context)
    #expect(opening(chili, scale: .servings(3)).picked.count == 3)
    #expect(opening(chili, scale: .servings(6)).picked.count == 5)
    #expect(opening(chili, scale: .servings(6)).summary == "5 of 6 servings planned")
    #expect(opening(chili, scale: .servings(1)).picked == [today])
    // Twice a batch of five.
    #expect(opening(chili, scale: .multiplier(2)).picked.count == 5)
    #expect(opening(chili, scale: .multiplier(2)).summary == "5 of 10 servings planned")
    #expect(opening(chili, scale: .multiplier(0.25)).picked == [today])
  }

  @Test func anEditedTotalDrivesSpreadShortcutsAndCompletion() throws {
    let context = try context()
    var plan = opening(recipe(servings: nil, in: context))
    plan.setTotal(4)
    plan.spreadOneADay()
    #expect(plan.totalServings == 4 && plan.planned == 4 && plan.unassigned == 0)
    #expect(plan.isComplete && plan.canStir && plan.picked.count == 4)
    #expect(plan.summary == "4 of 4 servings planned")
    plan.setTotal(2)
    #expect(plan.totalServings == 4)
    plan.toggle(plan.picked[0])
    plan.putAllOnAnchor()
    #expect(plan.planned == 4 && plan.isComplete)
  }

  @Test func theScaledTotalIsWorkedOutFromTheScale() {
    #expect(WeekPlan.batchServings(for: .servings(6), recipeServings: 4) == 6)
    #expect(WeekPlan.batchServings(for: .servings(3), recipeServings: nil) == 3)
    #expect(WeekPlan.batchServings(for: .multiplier(1.5), recipeServings: 4) == 6)
    #expect(WeekPlan.batchServings(for: .multiplier(0.25), recipeServings: 2) == 1)
    #expect(WeekPlan.batchServings(for: .multiplier(2), recipeServings: nil) == nil)
    #expect(WeekPlan.batchServings(for: .multiplier(1), recipeServings: nil) == nil)
    #expect(WeekPlan.batchServings(for: .servings(0), recipeServings: 4) == 4)
    #expect(
      WeekPlan.batchServings(for: .servings(WeekLimits.servings + 1), recipeServings: 4) == 4)
    #expect(
      WeekPlan.batchServings(for: .multiplier(8), recipeServings: WeekLimits.servings)
        == WeekLimits.servings)
  }

  // MARK: Changing the starting day

  @Test func changingTheStartingDayRedoesTheDefaultFromTheNewDay() throws {
    let context = try context()
    var plan = opening(recipe(servings: 5, in: context))
    plan = plan.started(on: today.adding(days: 3))
    #expect(plan.anchor == today.adding(days: 3))
    #expect(plan.days == today.startOfWeek().weekDays())
    #expect(plan.picked == [today.adding(days: 3), today.adding(days: 4)])
    #expect(plan.entries.allSatisfy { $0.servings == 1 })
  }

  @Test func changingTheMealDoesNotCountAsAHandEdit() throws {
    let context = try context()
    var plan = opening(recipe(servings: 5, in: context))
    plan.slot = .lunch
    #expect(plan.isUntouched)
    plan = plan.started(on: today.adding(days: 1))
    #expect(plan.slot == .lunch)
    #expect(plan.picked.count == 4 && plan.picked.first == today.adding(days: 1))
  }

  @Test func aHandEditedSpreadKeepsItsShapeWhenTheStartingDayMoves() throws {
    let context = try context()
    var plan = opening(recipe(servings: 5, in: context))
    // Eating out on the second day, and two servings on the last.
    plan.toggle(today.adding(days: 1))
    plan.step(today.adding(days: 4), by: 1)
    #expect(!plan.isUntouched)
    let before = plan.entries

    plan = plan.started(on: today.adding(days: 2))
    #expect(plan.anchor == today.adding(days: 2))
    #expect(plan.days == today.startOfWeek().weekDays())
    #expect(plan.entries.map(\.servings) == before.map(\.servings))
    #expect(plan.entries.map(\.date) == before.map(\.date))
    // Four days picked: 1, 1, 1, 2.
    #expect(plan.entries.map(\.servings) == [1, 1, 1, 2])
    #expect(plan.picked.count == 4)
  }

  @Test func aSpreadPutAllOnOneDayCountsAsEditedToo() throws {
    let context = try context()
    var plan = opening(recipe(servings: 5, in: context))
    plan.putAllOnAnchor()
    #expect(!plan.isUntouched)
    plan = plan.started(on: today.adding(days: 1))
    #expect(plan.entries == [DayServings(date: today, servings: 5)])
  }

  @Test func handEditingBackToTheDefaultIsUntouchedAgain() throws {
    let context = try context()
    var plan = opening(recipe(servings: 3, in: context))
    plan.toggle(today.adding(days: 2))
    #expect(!plan.isUntouched)
    plan.toggle(today.adding(days: 2))
    #expect(plan.isUntouched)
  }

  // MARK: Writing

  @Test func stirringTheDefaultWritesOneEntryPerDayInTheChosenMeal() throws {
    let context = try context()
    let chili = recipe(servings: 5, in: context)
    var plan = opening(chili)
    plan.slot = .lunch
    let message = try WeekPlan.stir(chili, spread: plan, into: context)
    #expect(message == "Stirred into 5 days.")
    let written = try everything(context)
    #expect(written.map(\.dayKey) == (0..<5).map { today.adding(days: $0).description })
    #expect(written.allSatisfy { $0.slot == .lunch && $0.servings == 1 && $0.recipe === chili })
  }

  @Test func theMessageNamesOneDayWhenOneDayWasStirred() throws {
    let context = try context()
    let soup = recipe("Soup", servings: 1, in: context)
    let message = try WeekPlan.stir(soup, spread: opening(soup), into: context)
    #expect(message == "Stirred into 1 day.")
    #expect(try everything(context).count == 1)
  }

  @Test func aSpreadStaysInsideItsImmutableCalendarWeek() throws {
    let context = try context()
    let chili = recipe(servings: 5, in: context)
    // Saturday 10 October: Saturday and Sunday, then Monday to Wednesday of the next week.
    let saturday = LocalDate("2026-10-10")!
    let plan = SpreadPlan.batch(anchor: saturday, slot: .dinner, servings: 5)
    _ = try WeekPlan.stir(chili, spread: plan, into: context)

    let thisWeek = try WeekPlan.fetch(
      from: LocalDate("2026-10-05")!, through: LocalDate("2026-10-11")!, in: context)
    let nextWeek = try WeekPlan.fetch(
      from: LocalDate("2026-10-12")!, through: LocalDate("2026-10-18")!, in: context)
    #expect(thisWeek.map(\.dayKey) == ["2026-10-10", "2026-10-11"])
    #expect(nextWeek.isEmpty)
    let batch = try #require(
      try WeekPlan.batches(
        from: LocalDate("2026-10-05")!, through: LocalDate("2026-10-11")!, in: context
      ).first)
    #expect(batch.weekStartKey == "2026-10-05")
    #expect(batch.totalServings == 5 && WeekPlan.assignedServings(batch) == 2)
    #expect(WeekPlan.unassignedServings(batch) == 3)
    #expect(thisWeek.allSatisfy { $0.batch === batch })
  }

  @Test func anUnassignedBatchPersistsAndCanReceiveAssignmentsLater() throws {
    let context = try context()
    let chili = recipe(servings: nil, in: context)
    let batch = try WeekPlan.createBatch(
      recipe: chili, weekStart: today.weekDays()[0], totalServings: 3, in: context)
    try context.save()
    #expect(try context.fetchCount(FetchDescriptor<PlannedBatchRecord>()) == 1)
    #expect(try context.fetchCount(FetchDescriptor<PlanEntryRecord>()) == 0)
    let entry = try WeekPlan.assign(2, on: today, slot: .dinner, to: batch, in: context)
    #expect(entry.batch === batch && entry.recipe === chili)
    #expect(WeekPlan.unassignedServings(batch) == 1)
  }

  @Test func aFullMealRefusesAndNothingIsWritten() throws {
    let context = try context()
    let chili = recipe(servings: 5, in: context)
    // The third day's dinner is full.
    let full = MealTarget(day: today.adding(days: 2), slot: .dinner)
    for index in 0..<WeekLimits.perSlot {
      try WeekPlan.commit(in: context) {
        try WeekPlan.stirText("Dinner \(index)", at: full, into: context)
      }
    }
    let plan = opening(chili)
    #expect(throws: WeekPlanError.slotFull) {
      try WeekPlan.stir(chili, spread: plan, into: context)
    }
    let after = try everything(context)
    #expect(after.count == WeekLimits.perSlot)
    #expect(after.allSatisfy { $0.recipe == nil && $0.dayKey == full.day.description })
  }

  @Test func aBanishedRecipeCannotBePlannedAndNothingIsWritten() throws {
    let context = try context()
    let chili = recipe(servings: 5, in: context)
    RecipeLibrary.banish(chili)
    let plan = opening(chili)
    #expect(throws: WeekPlanError.recipeBanished) {
      try WeekPlan.stir(chili, spread: plan, into: context)
    }
    #expect(try everything(context).isEmpty)
  }

  @Test func aSpreadWithNoDayAssignmentsStillPersistsItsBatch() throws {
    let context = try context()
    let soup = recipe("Soup", servings: 1, in: context)
    var plan = opening(soup)
    plan.toggle(today)
    #expect(plan.canStir)
    try WeekPlan.stir(soup, spread: plan, into: context)
    #expect(try everything(context).isEmpty)
    #expect(
      try WeekPlan.batches(
        from: today.startOfWeek(), through: today.startOfWeek().adding(days: 6), in: context
      ).count == 1)
  }

  @Test func whatTheCookSeesForARefusalIsPlain() {
    #expect(WeekPlan.message(for: WeekPlanError.slotFull).text == Copy.week.slotFull.text)
    #expect(WeekPlan.message(for: WeekPlanError.recipeBanished).text == Copy.week.couldntSave.text)
  }
}
