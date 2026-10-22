import CauldronKit
import Foundation
import Testing

@testable import Cauldron

@Suite("Week presentation")
struct WeekPresentationTests {
  private let monday = LocalDate("2026-10-05")!
  private let en = Locale(identifier: "en_US")
  private var week: [LocalDate] { monday.weekDays() }

  // MARK: Dates

  @Test func daysAreLabelledInTheViewersLocale() {
    let wednesday = monday.adding(days: 2)
    #expect(WeekDates.weekday(wednesday, long: true, locale: en) == "Wednesday")
    #expect(WeekDates.weekday(wednesday, long: false, locale: en) == "Wed")
    #expect(WeekDates.dayOfMonth(wednesday) == "7")
    #expect(WeekDates.label(wednesday, long: true, locale: en) == "Wednesday, Oct 7")
    #expect(WeekDates.label(wednesday, long: false, locale: en) == "Wed, Oct 7")
    #expect(WeekDates.monthDay(wednesday, locale: en) == "Oct 7")
  }

  @Test func aWeekRangeCrossesMonthsAndYears() {
    #expect(WeekDates.rangeLabel(start: LocalDate("2026-09-28")!, locale: en) == "Sep 28 – Oct 4")
    #expect(WeekDates.rangeLabel(start: LocalDate("2026-12-28")!, locale: en) == "Dec 28 – Jan 3")
  }

  @Test func todayIsTheDayOnTheCooksOwnCalendar() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
    // 23:30 on the 10th in Auckland is the 10th there, whatever day it is in UTC.
    let late = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23, minute: 30)))
    #expect(WeekDates.today(now: late, calendar: calendar) == LocalDate("2026-10-10"))
  }

  // MARK: Figures

  @Test func figuresRoundHalvesUpAndGroup() {
    #expect(WeekFigures.whole(1679.5, locale: en) == "1,680")
    #expect(WeekFigures.whole(2.5, locale: en) == "3")
    #expect(WeekFigures.whole(0.4, locale: en) == "0")
    #expect(WeekFigures.whole(.nan, locale: en) == "0")
  }

  @Test func theSplitBarSharesCaloriesByTheirEnergyPerGram() {
    // 10 g protein (40), 10 g carbs (40), 10 g fat (90): 170 in all.
    let split = WeekFigures.split(MacroTotals(calories: 0, protein: 10, carbs: 10, fat: 10))
    #expect(split.map(\.key) == [.protein, .carbs, .fat])
    #expect(abs(split[0].share - 40.0 / 170) < 1e-9)
    #expect(abs(split[2].share - 90.0 / 170) < 1e-9)
    #expect(WeekFigures.split(.zero).isEmpty)
  }

  @Test func theDailyAverageNeedsMoreThanOneDay() {
    let tally = tallyMacros([])
    #expect(WeekFigures.average(of: tally, daysPlanned: 3, locale: en) == nil)
  }

  // MARK: Spreading

  private func spread(servings: Int? = 4, from day: Int = 0) -> SpreadPlan {
    SpreadPlan(
      days: week, anchor: monday.adding(days: day), slot: .dinner, recipeServings: servings)
  }

  @Test func aSpreadStartsWithOneServingOnTheDayItWasStartedFrom() {
    let plan = spread(from: 2)
    #expect(plan.entries == [DayServings(date: monday.adding(days: 2), servings: 1)])
    #expect(plan.planned == 1 && plan.canStir && !plan.isOver)
    #expect(plan.summary == "1 of 4 servings planned")
  }

  @Test func daysAreToggledAndEntriesComeOutInWeekOrder() {
    var plan = spread(from: 3)
    plan.toggle(monday)
    plan.toggle(monday.adding(days: 5))
    plan.toggle(monday.adding(days: 3))
    #expect(plan.entries.map(\.date) == [monday, monday.adding(days: 5)])
    plan.toggle(monday)
    plan.toggle(monday.adding(days: 5))
    #expect(plan.canStir)
    #expect(plan.summary == "0 of 4 servings planned")
  }

  @Test func steppingAddsServingsAndTheLastOneOffDropsTheDay() {
    var plan = spread()
    plan.step(monday, by: 1)
    plan.step(monday, by: 1)
    #expect(plan.servings(on: monday) == 3)
    plan.step(monday, by: -3)
    #expect(plan.servings(on: monday) == nil)
    plan.step(monday, by: -1)
    #expect(plan.servings(on: monday) == nil)
    plan.step(monday.adding(days: 1), by: 1)
    #expect(plan.servings(on: monday.adding(days: 1)) == 1)
  }

  @Test func servingsStopAtTheLimit() {
    var plan = spread()
    for _ in 0..<(WeekLimits.servings + 5) { plan.step(monday, by: 1) }
    #expect(plan.servings(on: monday) == WeekLimits.servings)
  }

  @Test func oneADayFillsFromTheStartUntilTheServingsRunOut() {
    var plan = spread(servings: 3, from: 4)
    plan.spreadOneADay()
    #expect(plan.entries.map(\.date) == [4, 5, 6].map { monday.adding(days: $0) })
    #expect(plan.entries.allSatisfy { $0.servings == 1 })
    var long = spread(servings: 5, from: 5)
    long.spreadOneADay()
    #expect(long.entries.map(\.date) == [5, 6].map { monday.adding(days: $0) })
  }

  @Test func allOnOneDayPutsTheWholeBatchThere() {
    var plan = spread(servings: 12, from: 1)
    plan.step(monday, by: 1)
    plan.putAllOnAnchor()
    #expect(plan.entries == [DayServings(date: monday.adding(days: 1), servings: 12)])
    var unknown = spread(servings: nil)
    unknown.putAllOnAnchor()
    #expect(unknown.planned == 1)
  }

  @Test func plannedMoreThanTheRecipeMakesIsFlagged() {
    var plan = spread(servings: 2)
    plan.step(monday, by: 2)
    #expect(plan.planned == 3 && plan.isOver)
    #expect(plan.summary == "3 of 2 servings planned")
    #expect(!spread(servings: nil).isOver)
  }

  @Test func allocationCopyNamesRemainingAndCompletedServings() {
    #expect(Copy.week.spread.remaining(3).text == "3 servings unassigned")
    #expect(Copy.week.spread.remaining(1).text == "1 serving unassigned")
    #expect(Copy.week.spread.allAssigned.text == "All servings assigned")
  }

  @Test func batchSummaryReportsRemainingAndConflictWithoutNegativeCounts() {
    let partial = BatchAllocationSummary(
      title: "Soup", total: 5, assigned: 2, hasInvalidEntries: false)
    #expect(partial.remaining == 3)
    #expect(partial.status == "3 servings unassigned")
    let complete = BatchAllocationSummary(
      title: "Soup", total: 2, assigned: 2, hasInvalidEntries: false)
    #expect(complete.status == "All servings assigned")
    let conflicted = BatchAllocationSummary(
      title: "Soup", total: 2, assigned: 4, hasInvalidEntries: true)
    #expect(conflicted.remaining == 0)
    #expect(conflicted.isConflict)
  }

  @Test func batchDraftDoesNotCallReducedCapacityCompleteAndUsesRaisedCapacity() {
    let conflict = BatchAllocationSummary(
      title: "Soup", total: 1, assigned: 2, hasInvalidEntries: false)
    #expect(conflict.isConflict)
    #expect(conflict.status == Copy.week.allocationConflict.text)
    #expect(conflict.remaining == 0)
    let increased = BatchAllocationSummary(
      title: "Soup", total: 5, assigned: 2, hasInvalidEntries: false)
    #expect(increased.assignable == 3)
    #expect(increased.status == "3 servings unassigned")
  }

  // MARK: Changing an entry

  private func meal(
    recipe: PlanRecipe? = nil, servings: Int? = nil, title: String = "Soup"
  ) -> PlanEntry {
    PlanEntry(
      id: UUID(), date: monday, slot: .dinner, title: title, recipe: recipe, servings: servings,
      position: 0, brewed: false)
  }

  private var soup: PlanRecipe {
    PlanRecipe(
      id: UUID(), title: "Soup", servings: 4, totalMinutes: 35, photoKey: nil,
      macros: Macros(calories: 260, protein: 12, carbs: 38, fat: 7))
  }

  @Test func anUntouchedDraftChangesNothing() {
    #expect(PlannedMealDraft(meal(recipe: soup, servings: 2)).change == nil)
    #expect(PlannedMealDraft(meal()).change == nil)
  }

  @Test func aDraftSaysOnlyWhatChanged() {
    var draft = PlannedMealDraft(meal(recipe: soup, servings: 2))
    draft.day = monday.adding(days: 1)
    draft.servings = nil
    #expect(draft.change == EntryChange(day: monday.adding(days: 1), servings: .some(nil)))
    draft.slot = .lunch
    #expect(draft.change?.slot == .lunch)
  }

  @Test func aRecipeEntryCantBeRenamedButFreeTextCan() {
    var recipeDraft = PlannedMealDraft(meal(recipe: soup))
    recipeDraft.title = "Other"
    #expect(recipeDraft.change == nil && !recipeDraft.canRename)

    var text = PlannedMealDraft(meal(title: "Leftovers"))
    #expect(text.canRename)
    text.title = "  Takeaway "
    #expect(text.change == EntryChange(title: "Takeaway"))
    text.title = "   "
    #expect(text.change == nil && !text.isValid)
  }

  @Test func freeTextHasNoServingsToChange() {
    var draft = PlannedMealDraft(meal(title: "Leftovers"))
    draft.servings = 3
    #expect(draft.change == nil)
  }
}
