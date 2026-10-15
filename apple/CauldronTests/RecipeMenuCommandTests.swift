import CauldronKit
import Testing

@testable import Cauldron

/// The Recipe menu's Duplicate and Print.
@MainActor
@Suite("Recipe menu: duplicate and print")
struct RecipeMenuCommandTests {
  private final class Calls {
    var count = 0
    func tick() { count += 1 }
  }

  private func commands(
    banished: Bool = false, calls: Calls = Calls(), withDuplicate: Bool = true
  ) -> RecipeCommands {
    RecipeCommands(
      isBanished: banished, edit: calls.tick, brew: calls.tick, stir: calls.tick,
      openInWindow: calls.tick, duplicate: withDuplicate ? calls.tick : nil,
      printRecipe: calls.tick)
  }

  @Test func duplicateIsCommandDAndPrintIsCommandP() {
    #expect(MenuCommand.duplicateRecipe.shortcut.key == "d")
    #expect(MenuCommand.duplicateRecipe.shortcut.modifiers == .command)
    #expect(MenuCommand.printRecipe.shortcut.key == "p")
    #expect(MenuCommand.printRecipe.shortcut.modifiers == .command)
  }

  @Test func theyAreNamedFromTheCopyModule() {
    let front = FrontWindow(recipe: commands())
    #expect(front.title(of: .duplicateRecipe) == Copy.recipeView.duplicate.text)
    #expect(front.title(of: .printRecipe) == Copy.recipeView.print.text)
  }

  @Test func bothNeedAnOpenRecipeAndABanishedOneCantBeCopied() {
    var front = FrontWindow(recipe: commands())
    #expect(front.isEnabled(.duplicateRecipe) && front.isEnabled(.printRecipe))
    front.recipe = commands(banished: true)
    #expect(!front.isEnabled(.duplicateRecipe))
    #expect(front.isEnabled(.printRecipe))
    front.recipe = commands(withDuplicate: false)
    #expect(!front.isEnabled(.duplicateRecipe))
    front.recipe = nil
    #expect(!front.isEnabled(.duplicateRecipe) && !front.isEnabled(.printRecipe))
  }

  @Test func eachRunsItsOwnClosureOnce() {
    let calls = Calls()
    let front = FrontWindow(recipe: commands(calls: calls))
    front.perform(.duplicateRecipe)
    #expect(calls.count == 1)
    front.perform(.printRecipe)
    #expect(calls.count == 2)
  }

  @Test func aBanishedRecipeIsNotCopiedByTheMenu() {
    let calls = Calls()
    FrontWindow(recipe: commands(banished: true, calls: calls)).perform(.duplicateRecipe)
    #expect(calls.count == 0)
  }
}
