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
    #expect(AddWay.available == [.recents, .recipe, .quick])
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
    #expect(DayNavigator.label(for: today.adding(days: -5), today: today).contains("5"))
  }
}
