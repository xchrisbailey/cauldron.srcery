import CauldronImports
import CauldronKit
import Foundation

extension RecipeDraft {
  /// A saved recipe, ready for the editor.
  init(_ recipe: RecipeRecord) {
    self.init()
    title = recipe.title
    summary = recipe.summary ?? ""
    servings = Self.text(recipe.servings)
    prepMinutes = Self.text(recipe.prepMinutes)
    cookMinutes = Self.text(recipe.cookMinutes)
    totalMinutes = Self.text(recipe.totalMinutes)
    let macros = recipe.macros
    calories = Self.text(macros.calories)
    protein = Self.text(macros.protein)
    carbs = Self.text(macros.carbs)
    fat = Self.text(macros.fat)
    sourceURL = recipe.sourceURL ?? ""
    notes = recipe.notes ?? ""
    tags = (recipe.tags ?? []).map(\.name).sorted()
    ingredientsLocked = !recipe.canRewriteIngredients
    stepsLocked = !recipe.canRewriteSteps

    let rows = withHeadings(recipe.ingredients).map { row -> IngredientRowDraft in
      switch row {
      case .heading(let name): .heading(name)
      case .line(let ingredient): .stored(ingredient)
      }
    }
    ingredients = rows.isEmpty ? [.line("")] : rows
    let stored = recipe.steps.map(StepRowDraft.stored)
    steps = stored.isEmpty ? [.blank()] : stored
  }
}
