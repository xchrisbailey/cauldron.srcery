#if os(macOS)
  import CauldronKit
  import SwiftUI

  /// The ids of the windows the app opens by name.
  enum WindowID {
    static let main = "main"
    static let recipe = "recipe"
  }

  /// The Mac's menu bar: New Recipe and the section's own Add in File, Find in Edit, a Go menu
  /// for the sections, today and the days or weeks either side, and a Recipe menu for the open
  /// recipe. Each item acts on the front window and is disabled when that window can't do it.
  /// What each one does and when it applies is `FrontWindow`; this only lays the menus out.
  struct CauldronCommands: Commands {
    @FocusedValue(\.navigationCommands) private var navigation
    @FocusedValue(\.libraryCommands) private var library
    @FocusedValue(\.recipeCommands) private var recipe
    @FocusedValue(\.addCommand) private var add
    @FocusedValue(\.stepCommands) private var steps
    @Environment(\.openWindow) private var openWindow

    private var front: FrontWindow {
      FrontWindow(
        navigation: navigation, library: library, recipe: recipe, add: add, steps: steps)
    }

    var body: some Commands {
      // New Recipe takes Command-N; New Window moves to Shift-Command-N.
      CommandGroup(replacing: .newItem) {
        item(.newRecipe)
        Button(Copy.macMenu.newWindow.text) { openWindow(id: WindowID.main) }
          .keyboardShortcut(MenuCommand.newWindowShortcut)
        Divider()
        item(.addMeal)
        item(.addItem)
        item(.logFood)
      }
      CommandGroup(after: .textEditing) {
        item(.findRecipes)
      }
      CommandMenu(Copy.macMenu.goMenu.text) {
        item(.goRecipes)
        item(.goWeek)
        item(.goGather)
        item(.goTracker)
        Divider()
        item(.goToToday)
        item(.previous)
        item(.next)
      }
      CommandMenu(Copy.pageTitles.recipe.text) {
        item(.editRecipe)
        item(.brewRecipe)
        item(.stirRecipe)
        Divider()
        item(.openRecipeInWindow)
      }
    }

    private func item(_ command: MenuCommand) -> some View {
      let front = front
      return Button(front.title(of: command)) { front.perform(command) }
        .keyboardShortcut(command.shortcut)
        .disabled(!front.isEnabled(command))
    }
  }
#endif
