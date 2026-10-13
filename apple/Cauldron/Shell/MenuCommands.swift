import CauldronKit
import SwiftUI

// What the Mac's menu bar can ask of the front window, kept apart from the menu itself so the
// rules can be tested: which command applies to which state, and what it does. Each screen
// publishes the commands it can answer with `focusedSceneValue`, so a command acts on the
// window in front and is disabled when the window can't do it. Nothing here is Mac-only; the
// menus that read it are in `CauldronCommands`.

/// Go to a section.
struct NavigationCommands {
  let go: (AppDestination) -> Void
}

/// The recipe library: add a recipe, find one, and distill one from a link or pasted text.
struct LibraryCommands {
  let newRecipe: () -> Void
  let find: () -> Void
  let importRecipe: () -> Void
}

/// The recipe that is open, in the library or in a window of its own.
struct RecipeCommands {
  /// A banished recipe can't be planned.
  let isBanished: Bool
  let edit: () -> Void
  let brew: () -> Void
  let stir: () -> Void
  /// Nil in a recipe's own window, which is already what it would open.
  let openInWindow: (() -> Void)?
}

/// The one thing a section adds, which is a different thing in each.
struct AddCommand {
  enum Kind: Equatable {
    /// A meal in the week.
    case meal
    /// An item on the Gather list.
    case item
    /// A food in the diary.
    case food
  }

  let kind: Kind
  let perform: () -> Void
}

/// Today and the days or weeks either side of it, for the section that has a cursor.
struct StepCommands {
  let previousTitle: String
  let nextTitle: String
  /// Whether the cursor is already on today, which leaves Go to Today nothing to do.
  let isToday: Bool
  let previous: () -> Void
  let next: () -> Void
  let today: () -> Void

  /// Week by week: the Week and Gather sections, which share a cursor.
  @MainActor
  static func weeks(_ cursor: WeekCursor) -> StepCommands {
    StepCommands(
      previousTitle: Copy.week.previousWeek.text, nextTitle: Copy.week.nextWeek.text,
      isToday: cursor.isCurrent, previous: cursor.previous, next: cursor.next,
      today: cursor.thisWeek)
  }

  /// Day by day: the diary. `show` moves it to another day.
  @MainActor
  static func days(
    showing day: LocalDate, today: LocalDate, show: @escaping (LocalDate) -> Void
  ) -> StepCommands {
    StepCommands(
      previousTitle: Copy.tracker.diary.previousDay.text,
      nextTitle: Copy.tracker.diary.nextDay.text, isToday: day == today,
      previous: { show(day.adding(days: -1)) }, next: { show(day.adding(days: 1)) },
      today: { show(today) })
  }
}

extension FocusedValues {
  @Entry var navigationCommands: NavigationCommands?
  @Entry var libraryCommands: LibraryCommands?
  @Entry var recipeCommands: RecipeCommands?
  @Entry var addCommand: AddCommand?
  @Entry var stepCommands: StepCommands?
}

/// A menu item that acts on the front window. New Window isn't one: it needs no window.
enum MenuCommand: CaseIterable {
  case newRecipe
  case importRecipe
  case findRecipes
  case addMeal
  case addItem
  case logFood
  case goRecipes
  case goWeek
  case goGather
  case goTracker
  case goToToday
  case previous
  case next
  case editRecipe
  case brewRecipe
  case stirRecipe
  case openRecipeInWindow

  /// The command that goes to a section; nil for Settings, which the Mac gives its own
  /// scene and Command-comma.
  static func go(to destination: AppDestination) -> MenuCommand? {
    switch destination {
    case .recipes: .goRecipes
    case .week: .goWeek
    case .gather: .goGather
    case .tracker: .goTracker
    case .settings: nil
    }
  }

  /// New Window, which moved from Command-N to make room for New Recipe.
  static let newWindowShortcut = KeyboardShortcut("n", modifiers: [.command, .shift])

  var shortcut: KeyboardShortcut {
    switch self {
    case .newRecipe: KeyboardShortcut("n", modifiers: .command)
    // D for Distill; Shift-Command-I is Add Item.
    case .importRecipe: KeyboardShortcut("d", modifiers: [.command, .shift])
    case .findRecipes: KeyboardShortcut("f", modifiers: .command)
    case .addMeal: KeyboardShortcut("m", modifiers: [.command, .shift])
    case .addItem: KeyboardShortcut("i", modifiers: [.command, .shift])
    case .logFood: KeyboardShortcut("l", modifiers: [.command, .shift])
    case .goRecipes: KeyboardShortcut("1", modifiers: .command)
    case .goWeek: KeyboardShortcut("2", modifiers: .command)
    case .goGather: KeyboardShortcut("3", modifiers: .command)
    case .goTracker: KeyboardShortcut("4", modifiers: .command)
    case .goToToday: KeyboardShortcut("t", modifiers: .command)
    case .previous: KeyboardShortcut("[", modifiers: .command)
    case .next: KeyboardShortcut("]", modifiers: .command)
    case .editRecipe: KeyboardShortcut("e", modifiers: .command)
    case .brewRecipe: KeyboardShortcut("b", modifiers: .command)
    case .stirRecipe: KeyboardShortcut("s", modifiers: [.command, .shift])
    case .openRecipeInWindow: KeyboardShortcut("o", modifiers: [.command, .shift])
    }
  }
}

/// Everything the front window has published, and so what the menus can do right now.
struct FrontWindow {
  var navigation: NavigationCommands?
  var library: LibraryCommands?
  var recipe: RecipeCommands?
  var add: AddCommand?
  var steps: StepCommands?

  func isEnabled(_ command: MenuCommand) -> Bool {
    switch command {
    case .goRecipes, .goWeek, .goGather, .goTracker: navigation != nil
    case .newRecipe, .importRecipe, .findRecipes: library != nil
    case .addMeal: add?.kind == .meal
    case .addItem: add?.kind == .item
    case .logFood: add?.kind == .food
    case .goToToday: steps.map { !$0.isToday } ?? false
    case .previous, .next: steps != nil
    case .editRecipe, .brewRecipe: recipe != nil
    case .stirRecipe: recipe.map { !$0.isBanished } ?? false
    case .openRecipeInWindow: recipe?.openInWindow != nil
    }
  }

  func title(of command: MenuCommand) -> String {
    switch command {
    case .newRecipe: Copy.macMenu.newRecipe.text
    case .importRecipe: Copy.macMenu.importRecipe.text
    case .findRecipes: Copy.macMenu.findRecipes.text
    case .addMeal: Copy.macMenu.addMeal.text
    case .addItem: Copy.macMenu.addItem.text
    case .logFood: Copy.macMenu.logFood.text
    case .goRecipes: AppDestination.recipes.title.text
    case .goWeek: AppDestination.week.title.text
    case .goGather: AppDestination.gather.title.text
    case .goTracker: AppDestination.tracker.title.text
    case .goToToday: Copy.macMenu.goToToday.text
    case .previous: steps?.previousTitle ?? Copy.macMenu.previous.text
    case .next: steps?.nextTitle ?? Copy.macMenu.next.text
    case .editRecipe: Copy.recipeView.edit.text
    case .brewRecipe: Copy.recipes.startBrewing.text
    case .stirRecipe: Copy.week.stirIntoWeek.text
    case .openRecipeInWindow: Copy.macMenu.openInNewWindow.text
    }
  }

  /// Runs the command, or does nothing when the window can't do it.
  @MainActor
  func perform(_ command: MenuCommand) {
    guard isEnabled(command) else { return }
    switch command {
    case .goRecipes: navigation?.go(.recipes)
    case .goWeek: navigation?.go(.week)
    case .goGather: navigation?.go(.gather)
    case .goTracker: navigation?.go(.tracker)
    case .newRecipe: library?.newRecipe()
    case .importRecipe: library?.importRecipe()
    case .findRecipes: library?.find()
    case .addMeal, .addItem, .logFood: add?.perform()
    case .goToToday: steps?.today()
    case .previous: steps?.previous()
    case .next: steps?.next()
    case .editRecipe: recipe?.edit()
    case .brewRecipe: recipe?.brew()
    case .stirRecipe: recipe?.stir()
    case .openRecipeInWindow: recipe?.openInWindow?()
    }
  }
}
