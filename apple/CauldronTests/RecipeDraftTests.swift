import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Recipe draft")
struct RecipeDraftTests {
  private func context() throws -> ModelContext {
    ModelContext(try CauldronStore.container(.inMemory))
  }

  private func ingredient(
    _ original: String, section: String? = nil, item: String? = nil, quantity: Double? = nil,
    unit: UnitCode? = nil
  ) -> Ingredient {
    Ingredient(
      section: section, quantity: quantity.map { Quantity(min: $0, max: nil) }, unit: unit,
      item: item ?? original, note: nil, optional: false, alt: nil, original: original,
      itemKey: ingredientKey(item ?? original))
  }

  private func texts(_ draft: RecipeDraft) -> [String] { draft.ingredients.map(\.text) }

  // MARK: Starting points

  @Test func aNewDraftIsBlankWithOneEmptyLineAndStep() {
    let draft = RecipeDraft()
    #expect(draft.title.isEmpty)
    #expect(draft.ingredients.count == 1)
    #expect(draft.ingredients[0].text.isEmpty)
    #expect(draft.steps.count == 1)
    #expect(draft.photo == .keep)
    #expect(!draft.ingredientsLocked && !draft.stepsLocked)
  }

  @Test func aDraftFromARecipeCarriesEveryField() throws {
    let record = RecipeRecord(title: "Soup")
    try context().insert(record)
    record.summary = "Warm."
    record.servings = 4
    record.prepMinutes = 10
    record.cookMinutes = 25
    record.totalMinutes = 35
    record.sourceURL = "https://example.com/soup"
    record.notes = "Better next day."
    record.macros = Macros(calories: 260, protein: 12.5, carbs: 38, fat: 7)
    record.ingredients = [
      ingredient("1 cup beans", section: nil, item: "beans", quantity: 1, unit: .cup),
      ingredient("2 carrots", section: "Veg", item: "carrots", quantity: 2),
    ]
    record.steps = [Step(section: nil, text: "Simmer 10 minutes.", timerSeconds: 600)]
    let tag = TagRecord(name: "Lunch", kind: .meal)
    record.modelContext?.insert(tag)
    record.tags = [tag]

    let draft = RecipeDraft(record)
    #expect(draft.title == "Soup")
    #expect(draft.summary == "Warm.")
    #expect(draft.servings == "4")
    #expect(draft.prepMinutes == "10")
    #expect(draft.cookMinutes == "25")
    #expect(draft.totalMinutes == "35")
    #expect(draft.sourceURL == "https://example.com/soup")
    #expect(draft.notes == "Better next day.")
    #expect([draft.calories, draft.protein, draft.carbs, draft.fat] == ["260", "12.5", "38", "7"])
    #expect(draft.tags == ["Lunch"])
    // The heading is its own row, before the lines under it.
    #expect(texts(draft) == ["1 cup beans", "Veg", "2 carrots"])
    #expect(draft.ingredients.map(\.isHeading) == [false, true, false])
    #expect(draft.steps.map(\.text) == ["Simmer 10 minutes."])
    #expect(draft.steps[0].timerSeconds == 600)
  }

  @Test func aStoredLineKeepsItsStoredReadingUntilItsTextChanges() throws {
    let record = RecipeRecord(title: "Soup")
    try context().insert(record)
    // Read differently from what the parser would make of the text, as an earlier edit could.
    record.ingredients = [ingredient("some beans", item: "white beans", quantity: 3)]
    var draft = RecipeDraft(record)
    let id = draft.ingredients[0].id
    #expect(draft.ingredients[0].parsed?.item == "white beans")
    #expect(draft.ingredients[0].parsed?.quantity == Quantity(min: 3, max: nil))

    draft.setIngredientText(id, "2 cups flour")
    #expect(draft.ingredients[0].parsed?.item == "flour")
    #expect(draft.ingredients[0].parsed?.unit == .cup)
  }

  @Test func aRecipeWithNoLinesOrStepsStillOffersOneOfEach() throws {
    let record = RecipeRecord(title: "Toast")
    try context().insert(record)
    let draft = RecipeDraft(record)
    #expect(draft.ingredients.count == 1 && draft.steps.count == 1)
  }

  @Test func listsAnOlderBuildCouldntReadAreLockedNotEmptied() throws {
    let record = RecipeRecord(title: "Soup")
    try context().insert(record)
    record.ingredientsData = Data(
      #"[{"item":"beans","original":"beans","itemKey":"bean","optional":false},{"surprise":1}]"#
        .utf8)
    let draft = RecipeDraft(record)
    #expect(draft.ingredientsLocked)
    #expect(!draft.stepsLocked)
  }

  // MARK: Editing lines

  @Test func typingALineReadsItLive() {
    var draft = RecipeDraft()
    let id = draft.ingredients[0].id
    draft.setIngredientText(id, "1 1/2 cups flour, sifted")
    let parsed = draft.ingredients[0].parsed
    #expect(parsed?.quantity == Quantity(min: 1.5, max: nil))
    #expect(parsed?.unit == .cup)
    #expect(parsed?.item == "flour")
    #expect(parsed?.note == "sifted")
  }

  @Test func pastingAListSplitsItIntoLinesAndDropsBullets() {
    var draft = RecipeDraft()
    let id = draft.ingredients[0].id
    draft.setIngredientText(id, "- 2 eggs\n• 1 cup milk\n\n  ▢ salt")
    #expect(texts(draft) == ["2 eggs", "1 cup milk", "salt"])
  }

  @Test func returnEndsALineAndStartsABlankOneToMoveTo() {
    var draft = RecipeDraft()
    let id = draft.ingredients[0].id
    let next = draft.setIngredientText(id, "2 eggs\n")
    #expect(texts(draft) == ["2 eggs", ""])
    #expect(next == draft.ingredients[1].id)
    #expect(draft.ingredients[0].id == id)
    // Typing without a line break doesn't move anywhere.
    #expect(draft.setIngredientText(id, "3 eggs") == nil)
  }

  @Test func returnAfterATypedHeadingMakesItASectionRow() {
    var draft = RecipeDraft()
    draft.setIngredientText(draft.ingredients[0].id, "To serve:\n")
    #expect(draft.ingredients.map(\.isHeading) == [true, false])
  }

  @Test func theReadingShowsAmountUnitItemAndNote() {
    var draft = RecipeDraft()
    draft.setIngredientText(draft.ingredients[0].id, "1 1/2 cups flour, sifted")
    let reading = draft.ingredients[0].reading
    #expect(
      reading == .init(amount: "1 ½", unit: "c", item: "flour", note: "sifted", optional: false))
    draft.setIngredientText(draft.ingredients[0].id, "salt")
    #expect(
      draft.ingredients[0].reading
        == .init(amount: nil, unit: nil, item: "salt", note: nil, optional: false))
    #expect(!draft.ingredients[0].readingAddsToText)
    draft.setIngredientText(draft.ingredients[0].id, "2 eggs")
    #expect(draft.ingredients[0].readingAddsToText)
    draft.setIngredientText(draft.ingredients[0].id, "")
    #expect(draft.ingredients[0].reading == nil)
    #expect(!draft.ingredients[0].readingAddsToText)
  }

  @Test func aPastedHeadingBecomesASectionRow() {
    var draft = RecipeDraft()
    let id = draft.ingredients[0].id
    draft.setIngredientText(id, "For the sauce:\n1 cup cream")
    #expect(draft.ingredients.map(\.isHeading) == [true, false])
    #expect(texts(draft) == ["For the sauce", "1 cup cream"])
  }

  @Test func pastingInTheMiddleKeepsTheRowsAround() {
    var draft = RecipeDraft()
    draft.setIngredientText(draft.ingredients[0].id, "eggs")
    draft.addIngredient(after: draft.ingredients[0].id)
    draft.addIngredient(after: draft.ingredients[0].id)
    draft.setIngredientText(draft.ingredients[1].id, "milk\nflour")
    draft.setIngredientText(draft.ingredients[3].id, "salt")
    #expect(texts(draft) == ["eggs", "milk", "flour", "salt"])
  }

  @Test func aTypedHeadingIsReadWhenTheLineIsCommitted() {
    var draft = RecipeDraft()
    let id = draft.ingredients[0].id
    draft.setIngredientText(id, "To serve:")
    #expect(!draft.ingredients[0].isHeading)
    draft.commitIngredient(id)
    #expect(draft.ingredients[0].isHeading)
    #expect(draft.ingredients[0].text == "To serve")
  }

  @Test func ingredientsCanBeAddedMovedAndRemoved() {
    var draft = RecipeDraft()
    draft.setIngredientText(draft.ingredients[0].id, "a")
    draft.addIngredient(after: draft.ingredients[0].id)
    draft.setIngredientText(draft.ingredients[1].id, "b")
    draft.addHeading(after: draft.ingredients[1].id)
    #expect(draft.ingredients.map(\.isHeading) == [false, false, true])
    draft.moveIngredients(from: IndexSet(integer: 1), to: 0)
    #expect(Array(texts(draft).prefix(2)) == ["b", "a"])
    draft.removeIngredient(draft.ingredients[0].id)
    #expect(Array(texts(draft).prefix(1)) == ["a"])
  }

  @Test func removingTheLastLineLeavesOneBlankOne() {
    var draft = RecipeDraft()
    draft.removeIngredient(draft.ingredients[0].id)
    #expect(draft.ingredients.count == 1)
    draft.removeStep(draft.steps[0].id)
    #expect(draft.steps.count == 1)
  }

  // MARK: Editing steps

  @Test func aStepTakesItsTimerFromItsText() {
    var draft = RecipeDraft()
    let id = draft.steps[0].id
    draft.setStepText(id, "Bake 25 minutes.")
    #expect(draft.steps[0].timerSeconds == 1500)
    draft.setStepText(id, "Bake until golden.")
    #expect(draft.steps[0].timerSeconds == nil)
  }

  @Test func aTimerTheCookClearedStaysClearedWhileTheyKeepTyping() {
    var draft = RecipeDraft()
    let id = draft.steps[0].id
    draft.setStepText(id, "Bake 25 minutes.")
    draft.clearTimer(id)
    #expect(draft.steps[0].timerSeconds == nil)
    draft.setStepText(id, "Bake 30 minutes.")
    #expect(draft.steps[0].timerSeconds == nil)
  }

  @Test func aStoredStepKeepsItsSectionAndItsTimer() throws {
    let record = RecipeRecord(title: "Soup")
    try context().insert(record)
    record.steps = [Step(section: "Sauce", text: "Whisk.", timerSeconds: 90)]
    var draft = RecipeDraft(record)
    #expect(draft.steps[0].section == "Sauce")
    #expect(draft.steps[0].timerSeconds == 90)
    draft.setStepText(draft.steps[0].id, "Whisk well.")
    #expect(draft.steps[0].timerSeconds == 90)
  }

  @Test func pastingAMethodSplitsItIntoStepsWithoutTheirNumbers() {
    var draft = RecipeDraft()
    draft.setStepText(draft.steps[0].id, "1. Chop the onion.\n2. Fry it for 5 minutes.")
    #expect(draft.steps.map(\.text) == ["Chop the onion.", "Fry it for 5 minutes."])
    #expect(draft.steps[1].timerSeconds == 300)
  }

  @Test func returnInAStepStartsANewOneToMoveTo() {
    var draft = RecipeDraft()
    let id = draft.steps[0].id
    let next = draft.setStepText(id, "Chop the onion.\n")
    #expect(draft.steps.map(\.text) == ["Chop the onion.", ""])
    #expect(next == draft.steps[1].id)
    #expect(draft.steps[0].id == id)
  }

  @Test func pastingAMethodWithBlankLinesKeepsEachParagraphAsOneStep() {
    var draft = RecipeDraft()
    draft.setStepText(draft.steps[0].id, "Mix the dough\nuntil smooth.\n\nLet it rest.")
    #expect(draft.steps.map(\.text) == ["Mix the dough until smooth.", "Let it rest."])
  }

  // MARK: Tags

  @Test func tagsAreTrimmedAndNotRepeatedIgnoringCase() {
    var draft = RecipeDraft()
    draft.addTag("  Dinner ")
    draft.addTag("dinner")
    draft.addTag("")
    draft.addTag("Quick,")
    #expect(draft.tags == ["Dinner", "Quick"])
    draft.removeTag("DINNER")
    #expect(draft.tags == ["Quick"])
  }

  // MARK: Dirty

  @Test func aDraftIsDirtyOnceItDiffersFromWhereItStarted() {
    let start = RecipeDraft()
    var draft = start
    #expect(draft == start)
    draft.title = "Soup"
    #expect(draft != start)
  }
}
