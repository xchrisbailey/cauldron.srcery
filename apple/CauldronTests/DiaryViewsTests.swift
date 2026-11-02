import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

@MainActor
@Suite("Diary screens")
struct DiaryViewsTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!

  // Drawn without a navigation stack: SwiftUI stops with "no current update to enqueue action
  // to" when a stack holding the diary is drawn off screen on iOS. The shell test draws the
  // tracker root, stack and all, on its set-up.
  private func draws(_ view: some View) -> Bool {
    ImageRenderer(content: view.frame(width: 390, height: 800)).cgImage != nil
  }

  @Test func theDiaryDrawsASeededDayInBothAppearances() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    try DebugSeed.populate(context, today: today)
    let targets = try #require(try context.current(TargetsRecord.self))
    for scheme in [ColorScheme.light, .dark] {
      let view = DiaryView(today: today, targets: targets, openTargets: {})
        .modelContainer(container)
        .environment(\.colorScheme, scheme)
      #expect(draws(view), "\(scheme)")
    }
  }

  @Test func theDiaryDrawsAnEmptyDayWithAndWithoutTargets() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let targets = TargetsRecord(calories: 1450, protein: 134, carbs: 129, fat: 45)
    context.insert(targets)
    for record in [targets, nil] {
      let view = DiaryView(today: today, targets: record, openTargets: {})
        .modelContainer(container)
      #expect(draws(view))
    }
  }

  @Test func theAddSheetDrawsItsQuickAdd() throws {
    let container = try CauldronStore.container(.inMemory)
    let view = DiaryAddSheet(day: today, slot: .lunch) {}.modelContainer(container)
    #expect(draws(view))
    #expect(AddWay.available == [.recents, .describe, .recipe, .quick])
  }

  @Test func theEntrySheetDrawsAnEntry() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let record = DiaryEntryRecord(day: today, slot: .dinner, name: "Soup", source: .manual)
    record.macros = Macros(calories: 210, protein: 8, carbs: 30, fat: 6)
    context.insert(record)
    let sheet = DiaryEntrySheet(record: record, onClose: {}, onFailure: { _ in })
    let view = sheet.modelContainer(container)
    #expect(draws(view))
  }

  @Test func theDayIsNamedRelativeToToday() {
    #expect(DayNavigator.label(for: today, today: today) == "Today")
    #expect(DayNavigator.label(for: today.adding(days: -1), today: today) == "Yesterday")
    #expect(DayNavigator.label(for: today.adding(days: 1), today: today) == "Tomorrow")
    #expect(DayNavigator.label(for: today.adding(days: -5), today: today) == "Monday")
  }

  @Test func shownDatesStayGregorianUnderAnySystemCalendar() {
    // 2026-10-05 is a Monday; the navigator sits on the 10th, five days later.
    let day = today.adding(days: -5)
    for identifier in ["en_US", "en_US@calendar=japanese", "en_US@calendar=buddhist"] {
      let locale = Locale(identifier: identifier)
      #expect(
        DayNavigator.label(for: day, today: today, locale: locale) == "Monday",
        Comment(rawValue: identifier))
      #expect(
        CopyDaySheet.longLabel(of: day, locale: locale) == "Monday, Oct 5",
        Comment(rawValue: identifier))
      #expect(
        WeightEntrySheet.title(pickDay: false, day: day, locale: locale)
          == "Weigh-in for Oct 5", Comment(rawValue: identifier))
    }
    #expect(WeightEntrySheet.title(pickDay: true, day: day) == "Weigh-in")
  }

  @Test func noShownDateIsAnISODate() {
    let iso = /\d{4}-\d{2}-\d{2}/
    for day in [today.adding(days: -5), today.adding(days: -1)] {
      #expect(DayNavigator.label(for: day, today: today).wholeMatch(of: iso) == nil)
      #expect(CopyDaySheet.longLabel(of: day).firstMatch(of: iso) == nil)
      #expect(WeightEntrySheet.title(pickDay: false, day: day).firstMatch(of: iso) == nil)
      #expect(WeekDates.monthDay(day).firstMatch(of: iso) == nil)
    }
  }
}
