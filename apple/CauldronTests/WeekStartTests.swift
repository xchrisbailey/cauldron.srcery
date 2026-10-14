import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

/// The first day of the week as a preference, and everything that follows it.
@MainActor
@Suite("Week start")
struct WeekStartTests {
  /// A Wednesday.
  private let today = LocalDate("2026-10-14")!

  private func context() throws -> ModelContext {
    ModelContext(try CauldronStore.container(.inMemory))
  }

  private final class Offset {
    var value = 0
  }

  private func cursor(
    startsOn: WeekStartDay, offset: Offset = Offset(), today: LocalDate? = nil
  ) -> WeekCursor {
    WeekCursor(
      today: today ?? self.today, startsOn: startsOn,
      offset: Binding(get: { offset.value }, set: { offset.value = $0 }),
      setStartsOn: { _ in })
  }

  // MARK: The preference

  @Test func aCookWhoHasNotChosenStartsOnMonday() throws {
    #expect(WeekStartPreference.current([]) == .monday)
    #expect(PreferencesRecord().weekStartsOn == .monday)
  }

  @Test func anUnknownStoredValueFallsBackToMonday() throws {
    let record = PreferencesRecord()
    for raw in [7, 8, -1, 99] {
      record.weekStartsOnRaw = raw
      #expect(record.weekStartsOn == .monday, "\(raw)")
      #expect(WeekStartPreference.current([record]) == .monday, "\(raw)")
    }
  }

  @Test func everyDayIsStoredAsItsWeekdayNumberAndReadsBack() {
    let record = PreferencesRecord()
    for day in WeekStartDay.allCases {
      record.weekStartsOn = day
      #expect(record.weekStartsOnRaw == day.weekday.rawValue)
      #expect(record.weekStartsOn == day)
    }
    // Values written before the other days existed still mean what they did.
    record.weekStartsOnRaw = 0
    #expect(record.weekStartsOn == .sunday)
    record.weekStartsOnRaw = 1
    #expect(record.weekStartsOn == .monday)
  }

  @Test func settingTheDayMakesThePreferenceAndKeepsOneRow() throws {
    let context = try context()
    WeekStartPreference.set(.wednesday, preferences: [], in: context)
    var rows = try context.fetch(FetchDescriptor<PreferencesRecord>())
    #expect(rows.count == 1)
    #expect(WeekStartPreference.current(rows) == .wednesday)

    WeekStartPreference.set(.saturday, preferences: rows, in: context)
    rows = try context.fetch(FetchDescriptor<PreferencesRecord>())
    #expect(rows.count == 1)
    #expect(rows.first?.weekStartsOnRaw == 6)
    #expect(WeekStartPreference.current(rows) == .saturday)
  }

  @Test func settingTheDayLeavesTheOtherPreferencesAlone() throws {
    let context = try context()
    let record = PreferencesRecord()
    record.unitSystem = .metric
    context.insert(record)
    WeekStartPreference.set(.friday, preferences: [record], in: context)
    #expect(record.unitSystem == .metric)
    #expect(record.weekStartsOn == .friday)
  }

  @Test func settingsAndTheWeekPageShareThePicker() {
    // Seven days, each named once, in the order the cook reads them.
    #expect(WeekStartPicker.order.count == 7)
    #expect(Set(WeekStartPicker.order) == Set(WeekStartDay.allCases))
    #expect(
      WeekStartPicker.order.map { Copy.week.dayName($0).text } == [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
      ])
  }

  // MARK: What follows it

  @Test(
    "the week shown holds today, whatever the first day",
    arguments: WeekStartDay.allCases)
  func theShownWeekHoldsToday(_ startsOn: WeekStartDay) {
    for offset in 0..<14 {
      let day = today.adding(days: offset)
      let cursor = cursor(startsOn: startsOn, today: day)
      #expect(cursor.start.weekday == startsOn.weekday)
      #expect(cursor.start.weekDays().contains(day), "\(startsOn) \(day)")
      #expect(cursor.isCurrent)
    }
  }

  @Test func aWednesdayStartMidWeekShowsWednesdayToTuesday() {
    let cursor = cursor(startsOn: .wednesday, today: LocalDate("2026-10-19")!)
    #expect(cursor.start == LocalDate("2026-10-14")!)
    #expect(cursor.start.weekDays().last == LocalDate("2026-10-20")!)
    let before = self.cursor(startsOn: .wednesday, today: LocalDate("2026-10-13")!)
    #expect(before.start == LocalDate("2026-10-07")!)
  }

  @Test func theMenuStepsTheWeekFromANonMondayStart() {
    let offset = Offset()
    let cursor = cursor(startsOn: .thursday, offset: offset)
    // Thursday 8 October starts the week that holds Wednesday the 14th.
    #expect(cursor.start == LocalDate("2026-10-08")!)
    let commands = StepCommands.weeks(cursor)
    #expect(commands.isToday)
    commands.next()
    #expect(cursor.start == LocalDate("2026-10-15")!)
    commands.next()
    #expect(cursor.start == LocalDate("2026-10-22")!)
    commands.previous()
    commands.previous()
    commands.previous()
    #expect(cursor.start == LocalDate("2026-10-01")!)
    #expect(!StepCommands.weeks(cursor).isToday)
    commands.today()
    #expect(cursor.start == LocalDate("2026-10-08")!)
    #expect(StepCommands.weeks(cursor).isToday)
  }

  @Test func theCursorFollowsAPreferenceChangedInSettings() throws {
    let context = try context()
    let record = PreferencesRecord()
    context.insert(record)
    #expect(
      cursor(startsOn: WeekStartPreference.current([record])).start == LocalDate("2026-10-12")!)
    // Settings writes through the same code the Week page's picker does.
    WeekStartPreference.set(.sunday, preferences: [record], in: context)
    let rows = try context.fetch(FetchDescriptor<PreferencesRecord>())
    #expect(cursor(startsOn: WeekStartPreference.current(rows)).start == LocalDate("2026-10-11")!)
  }

  @Test func theWeekPlannerShowsSevenDaysFromANonMondayStart() throws {
    let context = try context()
    let start = LocalDate("2026-10-14")!
    let soup = RecipeRecord(title: "Soup")
    context.insert(soup)
    for (offset, slot) in [(-1, MealSlot.dinner), (0, .dinner), (6, .lunch), (7, .dinner)] {
      let entry = PlanEntryRecord(
        day: start.adding(days: offset), slot: slot, title: "Soup", servings: 2)
      context.insert(entry)
      entry.recipe = soup
    }
    try context.save()
    let snapshot = WeekSnapshot(
      start: start, records: try context.fetch(FetchDescriptor<PlanEntryRecord>()))
    #expect(snapshot.days == start.weekDays())
    #expect(snapshot.days.first == start && snapshot.days.last == start.adding(days: 6))
    #expect(snapshot.meals.map(\.date) == [start, start.adding(days: 6)])
  }

  @Test func theGatherListBelongsToTheWeekFromTheChosenStart() throws {
    let context = try context()
    func recipe(_ title: String, _ block: String) -> RecipeRecord {
      let record = RecipeRecord(title: title)
      record.servings = 2
      record.ingredients = readIngredientBlock([block]).map { line in
        Ingredient(
          section: line.section, quantity: line.quantity, unit: line.unit, item: line.item,
          note: line.note, optional: line.optional, alt: line.alt, original: line.original,
          itemKey: ingredientKey(line.item))
      }
      context.insert(record)
      return record
    }
    let carrots = recipe("Carrots", "3 carrots")
    let onions = recipe("Onions", "2 onions")
    for (day, soup) in [("2026-10-13", carrots), ("2026-10-14", onions)] {
      let entry = PlanEntryRecord(
        day: LocalDate(day)!, slot: .dinner, title: soup.title, servings: 2)
      context.insert(entry)
      entry.recipe = soup
    }
    try context.save()

    func items(week: LocalDate) throws -> [String] {
      try GatherPlan.commit(in: context) { try GatherPlan.rebuild(week: week, in: context) }
      let rows = try context.fetch(FetchDescriptor<GatherItemRecord>()).filter {
        $0.weekStart == week
      }
      return rows.map(\.itemKey).sorted()
    }
    // A Wednesday start puts Tuesday the 13th in the week before.
    let wednesday = try items(week: LocalDate("2026-10-14")!)
    let before = try items(week: LocalDate("2026-10-07")!)
    let monday = try items(week: LocalDate("2026-10-12")!)
    #expect(wednesday == ["onion"])
    #expect(before == ["carrot"])
    // A Monday start holds both in one week.
    #expect(monday == ["carrot", "onion"])
  }

  @Test func theSeededPlanStartsOnTheStandardDay() throws {
    #if DEBUG
      let context = try context()
      try DebugSeed.populate(context, today: today)
      let first = today.startOfWeek(startingOn: .standard)
      let entries = try WeekPlan.fetch(
        from: first, through: first.adding(days: 6), in: context)
      #expect(entries.count == 5)
      #expect(entries.first?.dayKey == first.description)
    #endif
  }

  // MARK: Settings

  @Test func settingsAndThePickerDrawInBothAppearances() throws {
    let container = try CauldronStore.container(.inMemory)
    let sync = SyncStatusModel(account: FakeICloudAccount(.synced))
    for scheme in [ColorScheme.light, .dark] {
      let settings = SettingsView()
        .environment(sync).environment(RecipeAIService.offline())
        .modelContainer(container).environment(\.colorScheme, scheme)
      #expect(ImageRenderer(content: settings.frame(width: 420, height: 900)).cgImage != nil)
      let section = Form { WeekStartSection() }
        .modelContainer(container).environment(\.colorScheme, scheme)
      #expect(ImageRenderer(content: section.frame(width: 420, height: 200)).cgImage != nil)
    }
  }
}
