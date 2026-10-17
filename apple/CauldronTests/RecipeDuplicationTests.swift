import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

/// Duplicating a recipe, ported from the API's "duplicates a recipe with its ingredients,
/// steps and tags" and "a duplicate keeps [the photo]", plus what a copy must not inherit.
@MainActor
@Suite("Duplicating a recipe")
struct RecipeDuplicationTests {
  private let context: ModelContext

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  private func original() throws -> RecipeRecord {
    let recipe = RecipeRecord(title: "Fork me")
    context.insert(recipe)
    recipe.summary = "A soup."
    recipe.notes = "Better the next day."
    recipe.servings = 4
    recipe.prepMinutes = 10
    recipe.cookMinutes = 30
    recipe.totalMinutes = 40
    recipe.sourcePlatform = .web
    recipe.sourceURL = "https://example.com/r"
    recipe.sourceAuthor = "Ada"
    recipe.ingredients = [
      Ingredient(
        section: nil, quantity: Quantity(min: 1, max: nil), unit: .cup, item: "red lentils",
        note: "rinsed", optional: false, alt: nil, original: "1 cup red lentils, rinsed",
        itemKey: ingredientKey("red lentils"))
    ]
    recipe.steps = [Step(section: nil, text: "Simmer.", timerSeconds: 600)]
    recipe.macros = Macros(calories: 320, protein: 18, carbs: 50, fat: 4)
    recipe.macrosSource = .estimated
    let tag = TagRecord(name: "Soup", kind: .meal)
    context.insert(tag)
    recipe.tags = [tag]
    recipe.refreshSearchText()
    try RecipeCooking.markCooked(
      recipe, on: try #require(LocalDate("2026-10-01")), context: context)
    return recipe
  }

  @Test func theCopyHasAFreshIdAndATitleFromTheCopyModule() throws {
    let recipe = try original()
    let copy = try RecipeDuplication.duplicate(recipe, context: context)
    #expect(copy.id != recipe.id)
    #expect(copy.title == Copy.recipes.copyOf("Fork me").text)
    #expect(recipe.title == "Fork me")
  }

  @Test func theCopyKeepsIngredientsStepsTagsSourceAndMacros() throws {
    let recipe = try original()
    let copy = try RecipeDuplication.duplicate(recipe, context: context)
    #expect(copy.ingredients == recipe.ingredients)
    #expect(copy.steps == recipe.steps)
    #expect((copy.tags ?? []).map(\.name) == ["Soup"])
    #expect(copy.sourceURL == "https://example.com/r")
    #expect(copy.sourceAuthor == "Ada")
    #expect(copy.sourcePlatform == .web)
    #expect(copy.summary == "A soup.")
    #expect(copy.notes == "Better the next day.")
    #expect(copy.servings == 4)
    #expect(
      [copy.prepMinutes, copy.cookMinutes, copy.totalMinutes] == [10, 30, 40])
    #expect(copy.macros == recipe.macros)
    #expect(copy.macrosSource == .estimated)
  }

  @Test func theCopyIsFoundBySearchOnItsOwnTitle() throws {
    let copy = try RecipeDuplication.duplicate(try original(), context: context)
    #expect(copy.searchText.contains("copy"))
    #expect(copy.searchText.contains("red lentils"))
    #expect(copy.searchText.contains("soup"))
  }

  @Test func theCopyHasNoCookingHistory() throws {
    let recipe = try original()
    let copy = try RecipeDuplication.duplicate(recipe, context: context)
    #expect(copy.lastCookedOn == nil)
    #expect((copy.cooks ?? []).isEmpty)
    #expect(recipe.lastCookedOn == LocalDate("2026-10-01"))
    #expect((recipe.cooks ?? []).count == 1)
  }

  @Test func theCopyIsNotOnTheWeekOrWaitingOnAnEstimate() throws {
    let recipe = try original()
    recipe.macrosPending = true
    let entry = PlanEntryRecord(
      day: try #require(LocalDate("2026-10-12")), slot: .dinner, title: "Fork me")
    context.insert(entry)
    entry.recipe = recipe
    let copy = try RecipeDuplication.duplicate(recipe, context: context)
    #expect((copy.planEntries ?? []).isEmpty)
    #expect(!copy.macrosPending)
    #expect((recipe.planEntries ?? []).count == 1)
  }

  @Test func aDuplicateKeepsThePhotoAsItsOwn() throws {
    let recipe = try original()
    let photo = PhotoRecord(imageData: Data([1, 2, 3]), width: 4, height: 3)
    context.insert(photo)
    photo.recipe = recipe
    let copy = try RecipeDuplication.duplicate(recipe, context: context)
    #expect(copy.photo?.imageData == Data([1, 2, 3]))
    #expect(copy.photo?.width == 4)
    #expect(copy.photo !== recipe.photo)
    // Banishing the copy for good must not take the original's photo with it.
    context.delete(copy)
    try context.save()
    #expect(recipe.photo?.imageData == Data([1, 2, 3]))
  }

  @Test func theCopyIsSavedAndListedBesideTheOriginal() throws {
    let recipe = try original()
    let copy = try RecipeDuplication.duplicate(recipe, context: context)
    let all = try context.fetch(FetchDescriptor<RecipeRecord>())
    #expect(Set(all.map(\.id)) == [recipe.id, copy.id])
    #expect(!copy.isBanished)
  }

  @Test func aLongTitleIsCutToTheLimit() throws {
    let recipe = RecipeRecord(title: String(repeating: "x", count: RecipeLimits.title))
    context.insert(recipe)
    let copy = try RecipeDuplication.duplicate(recipe, context: context)
    #expect(copy.title.count == RecipeLimits.title)
  }

  @Test func theOriginalIsLeftAsItWas() throws {
    let recipe = try original()
    let before = (recipe.ingredients, recipe.steps, recipe.title, recipe.updatedAt)
    try RecipeDuplication.duplicate(recipe, context: context)
    #expect(recipe.ingredients == before.0)
    #expect(recipe.steps == before.1)
    #expect(recipe.title == before.2)
    #expect(recipe.updatedAt == before.3)
  }

  @Test func theNoticeAfterACopySaysSoAndOffersNoUndo() {
    #expect(RecipeNotice.duplicated.text == Copy.recipeView.duplicated.text)
    #expect(RecipeNotice.duplicated.undoLabel == nil)
  }
}
