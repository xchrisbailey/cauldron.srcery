import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Recipe saver")
struct RecipeSaverTests {
  private let context: ModelContext

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  private func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
    try context.fetchCount(FetchDescriptor<Model>())
  }

  private func stored(title: String = "Soup") -> RecipeRecord {
    let record = RecipeRecord(title: title)
    context.insert(record)
    return record
  }

  private func filled() -> RecipeDraft {
    var draft = RecipeDraft()
    draft.title = "  Shakshuka  "
    draft.summary = "Eggs in sauce."
    draft.servings = " 4 "
    draft.prepMinutes = "10"
    draft.cookMinutes = "25"
    draft.sourceURL = " https://example.com/shakshuka "
    draft.notes = "Serve hot."
    draft.setIngredientText(draft.ingredients[0].id, "2 tbsp olive oil")
    draft.addIngredient(after: draft.ingredients[0].id)
    draft.setIngredientText(
      draft.ingredients[1].id, "For the sauce:\n1 onion, diced\n\n3 cloves garlic")
    draft.setStepText(draft.steps[0].id, "Simmer for 10 minutes.")
    draft.addTag("Breakfast")
    return draft
  }

  // MARK: Creating

  @Test func savingANewRecipeStoresEveryField() throws {
    let recipe = try RecipeSaver.save(filled(), into: nil, context: context)
    #expect(try count(RecipeRecord.self) == 1)
    #expect(recipe.title == "Shakshuka")
    #expect(recipe.summary == "Eggs in sauce.")
    #expect(recipe.servings == 4)
    #expect(recipe.prepMinutes == 10 && recipe.cookMinutes == 25)
    #expect(recipe.totalMinutes == nil)
    #expect(recipe.sourceURL == "https://example.com/shakshuka")
    #expect(recipe.notes == "Serve hot.")
    #expect(recipe.sourcePlatform == .manual)
    #expect(recipe.deletedAt == nil)
    #expect(recipe.tags?.map(\.name) == ["Breakfast"])
  }

  @Test func ingredientsAreStoredStructuredWithTheirSectionAndKey() throws {
    let recipe = try RecipeSaver.save(filled(), into: nil, context: context)
    let lines = recipe.ingredients
    #expect(lines.map(\.original) == ["2 tbsp olive oil", "1 onion, diced", "3 cloves garlic"])
    #expect(lines.map(\.section) == [nil, "For the sauce", "For the sauce"])
    #expect(lines[0].quantity == Quantity(min: 2, max: nil))
    #expect(lines[0].unit == .tbsp)
    #expect(lines[0].item == "olive oil")
    #expect(lines[0].itemKey == ingredientKey("olive oil"))
    #expect(lines[1].note == "diced")
    #expect(lines[2].unit == .clove)
  }

  @Test func stepsAreStoredWithTheirTimers() throws {
    let recipe = try RecipeSaver.save(filled(), into: nil, context: context)
    #expect(recipe.steps == [Step(section: nil, text: "Simmer for 10 minutes.", timerSeconds: 600)])
  }

  @Test func searchTextIsRebuiltSoTheRecipeCanBeFound() throws {
    let recipe = try RecipeSaver.save(filled(), into: nil, context: context)
    let found = RecipeLibrary.visible(
      [recipe], matching: "garlic breakfast shakshuka", sort: .title)
    #expect(found.count == 1)
  }

  @Test func blankLinesStepsAndEmptyHeadingsAreNotStored() throws {
    var draft = RecipeDraft()
    draft.title = "Toast"
    draft.addHeading()
    draft.setIngredientText(draft.ingredients[1].id, "")
    draft.addIngredient()
    draft.setIngredientText(draft.ingredients.last!.id, "bread")
    draft.addStep()
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(recipe.ingredients.map(\.original) == ["bread"])
    #expect(recipe.ingredients[0].section == nil)
    #expect(recipe.steps.isEmpty)
  }

  @Test func anInvalidDraftSavesNothing() throws {
    var draft = filled()
    draft.title = ""
    draft.servings = "many"
    #expect(throws: RecipeSaver.Failure.self) {
      try RecipeSaver.save(draft, into: nil, context: context)
    }
    #expect(try count(RecipeRecord.self) == 0)
    #expect(try count(TagRecord.self) == 0)
  }

  @Test func theFailureCarriesTheErrorsToShow() {
    var draft = filled()
    draft.title = ""
    do {
      try RecipeSaver.save(draft, into: nil, context: context)
      Issue.record("expected a failure")
    } catch RecipeSaver.Failure.invalid(let errors) {
      #expect(errors[.title]?.text == Copy.validation.required.text)
    } catch {
      Issue.record("unexpected \(error)")
    }
  }

  // MARK: Editing

  @Test func editingAChangesTheDraftNotTheRecipeUntilSave() throws {
    let recipe = stored()
    recipe.servings = 2
    var draft = RecipeDraft(recipe)
    draft.title = "Changed"
    draft.servings = "8"
    #expect(recipe.title == "Soup")
    #expect(recipe.servings == 2)
    try RecipeSaver.save(draft, into: recipe, context: context)
    #expect(recipe.title == "Changed")
    #expect(recipe.servings == 8)
    #expect(try count(RecipeRecord.self) == 1)
  }

  @Test func clearedFieldsBecomeUnknownNotZeroOrEmpty() throws {
    let recipe = stored()
    recipe.summary = "Old"
    recipe.servings = 4
    recipe.prepMinutes = 5
    recipe.notes = "Old"
    recipe.sourceURL = "https://example.com"
    recipe.macros = Macros(calories: 100, protein: 1, carbs: 2, fat: 3)
    var draft = RecipeDraft(recipe)
    draft.summary = ""
    draft.servings = ""
    draft.prepMinutes = " "
    draft.notes = ""
    draft.sourceURL = ""
    draft.calories = ""
    draft.protein = ""
    draft.carbs = ""
    draft.fat = ""
    try RecipeSaver.save(draft, into: recipe, context: context)
    #expect(recipe.summary == nil && recipe.servings == nil && recipe.prepMinutes == nil)
    #expect(recipe.notes == nil && recipe.sourceURL == nil)
    #expect(recipe.macros == Macros())
    #expect(recipe.macrosSource == nil)
  }

  @Test func whatTheEditorDoesntShowIsKept() throws {
    let recipe = stored()
    recipe.sourcePlatform = .instagram
    recipe.sourceAuthor = "Someone"
    recipe.lastCookedOn = LocalDate("2026-10-01")
    recipe.createdAt = Date(timeIntervalSince1970: 100)
    let draft = RecipeDraft(recipe)
    try RecipeSaver.save(draft, into: recipe, context: context)
    #expect(recipe.sourcePlatform == .instagram)
    #expect(recipe.sourceAuthor == "Someone")
    #expect(recipe.lastCookedOn == LocalDate("2026-10-01"))
    #expect(recipe.createdAt == Date(timeIntervalSince1970: 100))
  }

  @Test func savingStampsTheChange() throws {
    let recipe = stored()
    recipe.updatedAt = Date(timeIntervalSince1970: 0)
    let now = Date(timeIntervalSince1970: 5_000)
    try RecipeSaver.save(RecipeDraft(recipe), into: recipe, context: context, now: now)
    #expect(recipe.updatedAt == now)
  }

  // MARK: Macros

  @Test func macrosTypedHereAreManual() throws {
    var draft = RecipeDraft()
    draft.title = "Soup"
    draft.calories = "260"
    draft.protein = "12.5"
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(recipe.macros == Macros(calories: 260, protein: 12.5, carbs: nil, fat: nil))
    #expect(recipe.macrosSource == .manual)
  }

  @Test func macrosLeftAloneKeepTheirSource() throws {
    let recipe = stored()
    recipe.macros = Macros(calories: 300, protein: 10, carbs: 20, fat: 5)
    recipe.macrosSource = .estimated
    try RecipeSaver.save(RecipeDraft(recipe), into: recipe, context: context)
    #expect(recipe.macrosSource == .estimated)
    var draft = RecipeDraft(recipe)
    draft.calories = "310"
    try RecipeSaver.save(draft, into: recipe, context: context)
    #expect(recipe.macrosSource == .manual)
  }

  // MARK: Tags

  @Test func anExistingTagIsReusedIgnoringCase() throws {
    let existing = TagRecord(name: "Dinner", kind: .meal)
    context.insert(existing)
    var draft = RecipeDraft()
    draft.title = "Stew"
    draft.addTag("dinner")
    draft.addTag("Quick")
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(try count(TagRecord.self) == 2)
    #expect(recipe.tags?.contains { $0 === existing } == true)
    #expect(Set(recipe.tags?.map(\.name) ?? []) == ["Dinner", "Quick"])
    #expect(existing.kind == .meal)
  }

  @Test func removingATagTakesItOffTheRecipeButKeepsTheTag() throws {
    let recipe = try RecipeSaver.save(filled(), into: nil, context: context)
    var draft = RecipeDraft(recipe)
    draft.removeTag("Breakfast")
    try RecipeSaver.save(draft, into: recipe, context: context)
    #expect(recipe.tags?.isEmpty == true)
    #expect(try count(TagRecord.self) == 1)
  }

  @Test func theSameTagTypedTwiceMakesOneTag() throws {
    var draft = RecipeDraft()
    draft.title = "A"
    draft.addTag("Quick")
    try RecipeSaver.save(draft, into: nil, context: context)
    var second = RecipeDraft()
    second.title = "B"
    second.addTag("QUICK")
    try RecipeSaver.save(second, into: nil, context: context)
    #expect(try count(TagRecord.self) == 1)
  }

  // MARK: Lists this build can't read

  @Test func aLockedListIsNeverSavedOver() throws {
    let recipe = stored()
    let unreadable = Data(
      #"[{"item":"beans","original":"beans","itemKey":"bean","optional":false},{"new":1}]"#.utf8)
    recipe.ingredientsData = unreadable
    #expect(!recipe.canRewriteIngredients)
    var draft = RecipeDraft(recipe)
    draft.title = "Renamed"
    draft.setStepText(draft.steps[0].id, "Stir.")
    // Even a change to the shown rows can't reach the stored list.
    draft.addIngredient()
    draft.setIngredientText(draft.ingredients.last!.id, "salt")
    try RecipeSaver.save(draft, into: recipe, context: context)
    #expect(recipe.title == "Renamed")
    #expect(recipe.steps.map(\.text) == ["Stir."])
    #expect(recipe.ingredientsData == unreadable)
    #expect(!recipe.canRewriteIngredients)
  }

  @Test func aLockedMethodIsNeverSavedOver() throws {
    let recipe = stored()
    let unreadable = Data(#"[{"text":"Stir.","section":null},{"new":1}]"#.utf8)
    recipe.stepsData = unreadable
    var draft = RecipeDraft(recipe)
    #expect(draft.stepsLocked)
    draft.title = "Renamed"
    try RecipeSaver.save(draft, into: recipe, context: context)
    #expect(recipe.stepsData == unreadable)
    #expect(recipe.title == "Renamed")
  }

  // MARK: Photo

  private func photo(_ byte: UInt8 = 1) -> ProcessedPhoto {
    ProcessedPhoto(data: Data([byte]), width: 800, height: 600)
  }

  @Test func aNewPhotoIsStoredWithItsSize() throws {
    var draft = filled()
    draft.photo = .replace(photo())
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    #expect(recipe.photo?.imageData == Data([1]))
    #expect(recipe.photo?.width == 800 && recipe.photo?.height == 600)
  }

  @Test func replacingAPhotoKeepsOneRecord() throws {
    var draft = filled()
    draft.photo = .replace(photo(1))
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    var again = RecipeDraft(recipe)
    again.photo = .replace(photo(2))
    try RecipeSaver.save(again, into: recipe, context: context)
    #expect(recipe.photo?.imageData == Data([2]))
    #expect(try count(PhotoRecord.self) == 1)
  }

  @Test func removingAPhotoDeletesIt() throws {
    var draft = filled()
    draft.photo = .replace(photo())
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    var again = RecipeDraft(recipe)
    again.photo = .remove
    try RecipeSaver.save(again, into: recipe, context: context)
    #expect(recipe.photo == nil)
    #expect(try count(PhotoRecord.self) == 0)
  }

  @Test func keepingThePhotoLeavesItAlone() throws {
    var draft = filled()
    draft.photo = .replace(photo())
    let recipe = try RecipeSaver.save(draft, into: nil, context: context)
    try RecipeSaver.save(RecipeDraft(recipe), into: recipe, context: context)
    #expect(recipe.photo?.imageData == Data([1]))
  }
}
