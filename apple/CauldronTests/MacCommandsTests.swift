import CauldronKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

/// What the Mac's menu bar does and when it applies. A test can't press a key, so these drive
/// the same `FrontWindow` the menus read, with the commands each screen would publish.
@MainActor
@Suite("Mac menu commands")
struct MacCommandsTests {
  private let monday = LocalDate("2026-10-05")!

  /// Counts how often a command's closure ran.
  private final class Calls {
    var count = 0
    func tick() { count += 1 }
  }

  private func recipeCommands(
    banished: Bool = false, inOwnWindow: Bool = false, calls: Calls = Calls()
  ) -> RecipeCommands {
    RecipeCommands(
      isBanished: banished, edit: calls.tick, brew: calls.tick, stir: calls.tick,
      openInWindow: inOwnWindow ? nil : calls.tick)
  }

  private func steps(isToday: Bool = false, calls: Calls = Calls()) -> StepCommands {
    StepCommands(
      previousTitle: "Previous week", nextTitle: "Next week", isToday: isToday,
      previous: calls.tick, next: calls.tick, today: calls.tick)
  }

  // MARK: Shortcuts and titles

  @Test func noTwoCommandsShareAShortcut() {
    var seen = Set<String>()
    let shortcuts = MenuCommand.allCases.map(\.shortcut) + [MenuCommand.newWindowShortcut]
    for shortcut in shortcuts {
      let key = "\(shortcut.key.character)-\(shortcut.modifiers.rawValue)"
      #expect(seen.insert(key).inserted, "\(key) is used twice")
    }
  }

  @Test func theSectionsAreCommandOneToFourAndSettingsHasNone() {
    let numbers = AppDestination.sections.map { MenuCommand.go(to: $0) }
    #expect(numbers == [.goRecipes, .goWeek, .goGather, .goTracker])
    #expect(numbers.compactMap { $0?.shortcut.key.character } == ["1", "2", "3", "4"])
    #expect(numbers.compactMap { $0?.shortcut.modifiers }.allSatisfy { $0 == .command })
    #expect(MenuCommand.go(to: .settings) == nil)
  }

  @Test func newRecipeTakesCommandNAndNewWindowMovesToShiftCommandN() {
    #expect(MenuCommand.newRecipe.shortcut.key == "n")
    #expect(MenuCommand.newRecipe.shortcut.modifiers == .command)
    #expect(MenuCommand.newWindowShortcut.key == "n")
    #expect(MenuCommand.newWindowShortcut.modifiers == [.command, .shift])
  }

  @Test func everyCommandHasATitleFromTheCopyModule() {
    let front = FrontWindow()
    for command in MenuCommand.allCases {
      #expect(!front.title(of: command).isEmpty, "\(command)")
    }
    #expect(front.title(of: .newRecipe) == "New Recipe")
    #expect(front.title(of: .goToToday) == "Go to Today")
    #expect(front.title(of: .goWeek) == AppDestination.week.title.text)
    #expect(front.title(of: .stirRecipe) == Copy.week.stirIntoWeek.text)
    #expect(front.title(of: .brewRecipe) == Copy.recipes.startBrewing.text)
  }

  @Test func theStepItemsNameTheWeekOrTheDayTheSectionStepsBy() {
    #expect(FrontWindow().title(of: .previous) == "Previous")
    var week = FrontWindow()
    week.steps = StepCommands.weeks(cursor(offset: Offset()))
    #expect(week.title(of: .previous) == "Previous week")
    #expect(week.title(of: .next) == "Next week")
    var diary = FrontWindow()
    diary.steps = StepCommands.days(showing: monday, today: monday) { _ in }
    #expect(diary.title(of: .previous) == "Previous day")
    #expect(diary.title(of: .next) == "Next day")
  }

  // MARK: When a command applies

  @Test func aWindowThatPublishedNothingHasEveryCommandDisabled() {
    let front = FrontWindow()
    for command in MenuCommand.allCases {
      #expect(!front.isEnabled(command), "\(command)")
    }
  }

  @Test func theSectionsAreAlwaysThereToGoTo() {
    let front = FrontWindow(navigation: NavigationCommands { _ in })
    let enabled = MenuCommand.allCases.filter(front.isEnabled)
    #expect(enabled == [.goRecipes, .goWeek, .goGather, .goTracker])
  }

  @Test func theLibraryEnablesNewRecipeImportAndFind() {
    let front = FrontWindow(library: LibraryCommands(newRecipe: {}, find: {}, importRecipe: {}))
    #expect(
      MenuCommand.allCases.filter(front.isEnabled) == [.newRecipe, .importRecipe, .findRecipes])
  }

  @Test func importRecipeIsDistillOnShiftCommandD() {
    #expect(MenuCommand.importRecipe.shortcut.key == "d")
    #expect(MenuCommand.importRecipe.shortcut.modifiers == [.command, .shift])
    #expect(FrontWindow().title(of: .importRecipe) == "Import Recipe…")
  }

  @Test func eachSectionEnablesOnlyItsOwnAdd() {
    let kinds: [(AddCommand.Kind, MenuCommand)] = [
      (.meal, .addMeal), (.item, .addItem), (.food, .logFood),
    ]
    for (kind, command) in kinds {
      let front = FrontWindow(add: AddCommand(kind: kind) {})
      let adds = [MenuCommand.addMeal, .addItem, .logFood].filter(front.isEnabled)
      #expect(adds == [command], "\(kind)")
    }
  }

  @Test func theRecipeMenuNeedsAnOpenRecipeAndStirNeedsOneThatIsntBanished() {
    var front = FrontWindow(recipe: recipeCommands())
    let recipeItems: [MenuCommand] = [.editRecipe, .brewRecipe, .stirRecipe, .openRecipeInWindow]
    #expect(recipeItems.allSatisfy(front.isEnabled))

    front.recipe = recipeCommands(banished: true)
    #expect(front.isEnabled(.editRecipe) && front.isEnabled(.brewRecipe))
    #expect(!front.isEnabled(.stirRecipe), "a banished recipe can't be planned")

    front.recipe = recipeCommands(inOwnWindow: true)
    #expect(!front.isEnabled(.openRecipeInWindow), "its own window is already open")
    #expect(front.isEnabled(.editRecipe))

    front.recipe = nil
    #expect(!recipeItems.contains(where: front.isEnabled))
  }

  @Test func goToTodayHasNothingToDoOnTodayButStepsAlwaysWork() {
    var front = FrontWindow(steps: steps(isToday: false))
    #expect(front.isEnabled(.goToToday) && front.isEnabled(.previous) && front.isEnabled(.next))
    front.steps = steps(isToday: true)
    #expect(!front.isEnabled(.goToToday))
    #expect(front.isEnabled(.previous) && front.isEnabled(.next))
  }

  // MARK: What a command does

  @Test func goChangesTheDestination() {
    var destination = AppDestination.recipes
    let front = FrontWindow(navigation: NavigationCommands { destination = $0 })
    front.perform(.goTracker)
    #expect(destination == .tracker)
    front.perform(.goWeek)
    #expect(destination == .week)
    front.perform(.goGather)
    #expect(destination == .gather)
    front.perform(.goRecipes)
    #expect(destination == .recipes)
  }

  @Test func eachCommandRunsItsOwnClosureOnce() {
    let new = Calls()
    let importing = Calls()
    let find = Calls()
    let add = Calls()
    let edit = Calls()
    let brew = Calls()
    let stir = Calls()
    let window = Calls()
    let front = FrontWindow(
      library: LibraryCommands(
        newRecipe: new.tick, find: find.tick, importRecipe: importing.tick),
      recipe: RecipeCommands(
        isBanished: false, edit: edit.tick, brew: brew.tick, stir: stir.tick,
        openInWindow: window.tick),
      add: AddCommand(kind: .food, perform: add.tick))
    for command in [
      MenuCommand.newRecipe, .importRecipe, .findRecipes, .logFood, .editRecipe, .brewRecipe,
      .stirRecipe,
      .openRecipeInWindow,
    ] {
      front.perform(command)
    }
    #expect(
      [new, importing, find, add, edit, brew, stir, window].map(\.count)
        == [1, 1, 1, 1, 1, 1, 1, 1])
  }

  @Test func aCommandTheWindowCantAnswerDoesNothing() {
    let calls = Calls()
    let front = FrontWindow(
      recipe: recipeCommands(banished: true, calls: calls),
      add: AddCommand(kind: .item, perform: calls.tick),
      steps: steps(isToday: true, calls: calls))
    front.perform(.stirRecipe)
    front.perform(.addMeal)
    front.perform(.logFood)
    front.perform(.goToToday)
    front.perform(.newRecipe)
    front.perform(.goWeek)
    #expect(calls.count == 0)
  }

  // MARK: The cursors

  /// Stands in for the week cursor's offset, which a view holds in `@State`.
  private final class Offset {
    var value = 0
  }

  private func cursor(offset: Offset) -> WeekCursor {
    WeekCursor(
      today: monday, startsOn: .monday,
      offset: Binding(get: { offset.value }, set: { offset.value = $0 }),
      setStartsOn: { _ in })
  }

  @Test func theWeekStepsMoveTheCursorAndTodayComesBack() {
    let offset = Offset()
    let cursor = cursor(offset: offset)
    let commands = StepCommands.weeks(cursor)
    #expect(commands.isToday)
    commands.next()
    commands.next()
    #expect(offset.value == 2)
    #expect(cursor.start == monday.adding(days: 14))
    commands.previous()
    #expect(offset.value == 1)
    #expect(!StepCommands.weeks(cursor).isToday)
    commands.today()
    #expect(offset.value == 0)
    #expect(cursor.start == monday)
  }

  @Test func theDayStepsMoveTheDiaryOneDayAndTodayComesBack() {
    var shown: LocalDate?
    let today = monday
    let day = StepCommands.days(showing: today, today: today) { shown = $0 }
    #expect(day.isToday)
    day.previous()
    #expect(shown == today.adding(days: -1))
    day.next()
    #expect(shown == today.adding(days: 1))

    let away = StepCommands.days(showing: today.adding(days: -3), today: today) { shown = $0 }
    #expect(!away.isToday)
    away.previous()
    #expect(shown == today.adding(days: -4))
    away.next()
    #expect(shown == today.adding(days: -2))
    away.today()
    #expect(shown == today)
  }

  // MARK: Add Meal

  @Test func addMealStartsOnTheChosenDayElseTodayElseTheWeeksFirstDay() {
    let week = monday.weekDays()
    let later = monday.adding(days: 3)
    let outside = monday.adding(days: 30)
    #expect(
      WeekPlan.newMeal(chosen: later, week: week, today: monday)
        == MealTarget(day: later, slot: .dinner))
    #expect(
      WeekPlan.newMeal(chosen: nil, week: week, today: later)
        == MealTarget(day: later, slot: .dinner))
    #expect(
      WeekPlan.newMeal(chosen: outside, week: week, today: later)
        == MealTarget(day: later, slot: .dinner))
    #expect(
      WeekPlan.newMeal(chosen: nil, week: week, today: outside)
        == MealTarget(day: monday, slot: .dinner))
  }
}
