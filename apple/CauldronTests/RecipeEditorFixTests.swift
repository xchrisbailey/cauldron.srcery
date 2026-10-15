import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

/// Fixing how an ingredient line was read, a step's timer, and when a field's problem shows.
/// Ported from `IngredientRows.tsx`, `StepRows.tsx` and `RecipeEditor.tsx`, and the
/// `corrected` and `parseQuantity` cases of `apps/web/test/recipe-form.test.ts`.
@MainActor
@Suite("Recipe editor fixes")
struct RecipeEditorFixTests {
  private func draft(line: String) -> (draft: RecipeDraft, id: UUID) {
    var draft = RecipeDraft()
    let id = draft.ingredients[0].id
    draft.setIngredientText(id, line)
    return (draft, id)
  }

  private func row(_ draft: RecipeDraft, _ id: UUID) -> IngredientRowDraft? {
    draft.ingredients.first { $0.id == id }
  }

  // MARK: What was read

  @Test func eachLineShowsWhatWasReadIncludingTheSecondAmount() {
    let (draft, id) = draft(line: "1 1/2 cups (190g) flour, sifted")
    let reading = row(draft, id)?.reading
    #expect(reading?.amount == "1 ½")
    #expect(reading?.unit == "c")
    #expect(reading?.item == "flour")
    #expect(reading?.note == "sifted")
    #expect(reading?.alt == .init(amount: "190", unit: "g"))
    #expect(row(draft, id)?.readingAddsToText == true)
  }

  @Test func theReadingIsWhatWasReadNotAConversion() {
    // An eighth of a cup stays an eighth of a cup, so the cook sees what a fix would change.
    let (draft, id) = draft(line: "1/8 cup sugar")
    #expect(row(draft, id)?.reading?.amount == "⅛")
    #expect(row(draft, id)?.reading?.unit == "c")
  }

  @Test func unitsWithoutAShortFormAreNamed() {
    let (draft, id) = draft(line: "2 cloves garlic, minced")
    #expect(row(draft, id)?.reading?.unit == "clove")
    #expect(UnitCode.tsp.editorLabel == "tsp")
    #expect(UnitCode.pinch.editorLabel == "pinch")
  }

  @Test func optionalLinesSayOptional() {
    let (draft, id) = draft(line: "1 tsp chili flakes, optional")
    #expect(row(draft, id)?.reading?.optional == true)
  }

  // MARK: Fixing by hand

  @Test func theAmountCanBeCorrectedFromWhatIsTyped() {
    var (draft, id) = draft(line: "2 cups flour")
    #expect(row(draft, id)?.corrected == false)
    let accepted = draft.setIngredientQuantity(id, from: "1 1/2")
    #expect(accepted)
    #expect(row(draft, id)?.parsed?.quantity == Quantity(min: 1.5, max: nil))
    #expect(row(draft, id)?.corrected == true)
    let rangeAccepted = draft.setIngredientQuantity(id, from: "2-3")
    #expect(rangeAccepted)
    #expect(row(draft, id)?.parsed?.quantity == Quantity(min: 2, max: 3))
    // The line as typed is not touched.
    #expect(row(draft, id)?.text == "2 cups flour")
  }

  @Test func aBlankAmountMeansNoAmount() {
    var (draft, id) = draft(line: "2 cups flour")
    let accepted = draft.setIngredientQuantity(id, from: "  ")
    #expect(accepted)
    #expect(row(draft, id)?.parsed?.quantity == nil)
  }

  @Test func somethingThatIsntAnAmountChangesNothingAndSaysSo() {
    var (draft, id) = draft(line: "2 cups flour")
    let accepted = draft.setIngredientQuantity(id, from: "abc")
    #expect(!accepted)
    #expect(row(draft, id)?.parsed?.quantity == Quantity(min: 2, max: nil))
    #expect(row(draft, id)?.corrected == false)
  }

  @Test func theUnitItemNoteAndOptionalCanBeCorrected() {
    var (draft, id) = draft(line: "2 cups flour")
    draft.setIngredientUnit(id, .g)
    draft.setIngredientItem(id, "plain flour")
    draft.setIngredientNote(id, "sifted")
    draft.setIngredientOptional(id, true)
    let parsed = row(draft, id)?.parsed
    #expect(parsed?.unit == .g)
    #expect(parsed?.item == "plain flour")
    #expect(parsed?.note == "sifted")
    #expect(parsed?.optional == true)
    #expect(row(draft, id)?.corrected == true)

    draft.setIngredientUnit(id, nil)
    draft.setIngredientNote(id, "")
    #expect(row(draft, id)?.parsed?.unit == nil)
    #expect(row(draft, id)?.parsed?.note == nil)
  }

  @Test func resettingReadsTheLineFromItsTextAgain() {
    var (draft, id) = draft(line: "2 cups flour")
    draft.setIngredientItem(id, "plain flour")
    draft.setIngredientUnit(id, .g)
    draft.resetIngredient(id)
    #expect(row(draft, id)?.parsed?.item == "flour")
    #expect(row(draft, id)?.parsed?.unit == .cup)
    #expect(row(draft, id)?.corrected == false)
  }

  @Test func retypingTheLineReadsItAgainAndDropsTheFix() {
    var (draft, id) = draft(line: "2 cups flour")
    draft.setIngredientItem(id, "plain flour")
    draft.setIngredientText(id, "3 cups rice")
    #expect(row(draft, id)?.parsed?.item == "rice")
    #expect(row(draft, id)?.corrected == false)
  }

  @Test func aFixAnImporterFlaggedClearsTheFlag() {
    var draft = RecipeDraft()
    draft.ingredients = [.imported("some paprika", flagged: true)]
    let id = draft.ingredients[0].id
    #expect(draft.ingredients[0].flagged)
    draft.setIngredientItem(id, "smoked paprika")
    #expect(!draft.ingredients[0].flagged)
  }

  @Test func fixingAHeadingOrAMissingRowDoesNothing() {
    var draft = RecipeDraft()
    draft.setIngredientText(draft.ingredients[0].id, "To serve:\n")
    let heading = draft.ingredients[0].id
    draft.setIngredientItem(heading, "x")
    #expect(draft.ingredients[0].parsed == nil)
    draft.setIngredientItem(UUID(), "x")
    draft.resetIngredient(UUID())
  }

  @Test func aStoredLineIsCorrectedOnlyWhenItDiffersFromTheParsersReading() throws {
    let container = try CauldronStore.container(.inMemory)
    let record = RecipeRecord(title: "Soup")
    ModelContext(container).insert(record)
    func stored(_ original: String, item: String) -> Ingredient {
      let parsed = parseIngredientLine(original)
      return Ingredient(
        section: nil, quantity: parsed.quantity, unit: parsed.unit, item: item,
        note: parsed.note, optional: parsed.optional, alt: parsed.alt, original: original,
        itemKey: ingredientKey(item))
    }
    record.ingredients = [
      stored("2 tbsp butter", item: "butter"), stored("2 tbsp butter", item: "salted butter"),
    ]
    let draft = RecipeDraft(record)
    #expect(draft.ingredients.map(\.corrected) == [false, true])
    #expect(draft.ingredients[1].parsed?.item == "salted butter")
  }

  @Test func theCorrectedReadingIsWhatSaveStores() throws {
    let container = try CauldronStore.container(.inMemory)
    var (draft, id) = draft(line: "2 cups flour")
    draft.title = "Bread"
    draft.setIngredientQuantity(id, from: "250")
    draft.setIngredientUnit(id, .g)
    draft.setIngredientItem(id, "strong flour")
    let recipe = try RecipeSaver.save(draft, into: nil, context: ModelContext(container))
    let stored = try #require(recipe.ingredients.first)
    #expect(stored.quantity == Quantity(min: 250, max: nil))
    #expect(stored.unit == .g)
    #expect(stored.item == "strong flour")
    #expect(stored.original == "2 cups flour")
    #expect(stored.itemKey == ingredientKey("strong flour"))
  }

  @Test func aFixThatLeavesNoItemIsAProblem() {
    var (draft, id) = draft(line: "2 cups flour")
    draft.title = "Bread"
    draft.setIngredientItem(id, "")
    #expect(draft.validate()[.ingredient(id)] == Copy.validation.required)
    draft.setIngredientItem(id, "flour")
    #expect(draft.validate().isEmpty)
    // A backwards range can't be typed into the amount field.
    let backwards = draft.setIngredientQuantity(id, from: "5-2")
    #expect(!backwards)
    #expect(draft.validate().isEmpty)
    draft.correctIngredient(id) { $0.quantity = Quantity(min: 5, max: 2) }
    #expect(draft.validate()[.ingredient(id)] == Copy.validation.range)
  }

  // MARK: Step timers

  private func stepDraft(_ text: String) -> (draft: RecipeDraft, id: UUID) {
    var draft = RecipeDraft()
    let id = draft.steps[0].id
    draft.setStepText(id, text)
    return (draft, id)
  }

  @Test func aTimerCanBeAddedToAStepThatHasNone() {
    var (draft, id) = stepDraft("Rest the dough.")
    #expect(draft.steps[0].timerSeconds == nil)
    draft.setTimer(id, minutes: "25")
    #expect(draft.steps[0].timerSeconds == 1500)
    // Set by hand, it no longer follows the text.
    draft.setStepText(id, "Rest the dough for 5 minutes.")
    #expect(draft.steps[0].timerSeconds == 1500)
  }

  @Test func aTimerTheTextGaveCanBeChanged() {
    var (draft, id) = stepDraft("Bake 25 minutes.")
    #expect(draft.steps[0].timerSeconds == 1500)
    draft.setTimer(id, minutes: "1.5")
    #expect(draft.steps[0].timerSeconds == 90)
    #expect(draft.steps[0].timerSet)
  }

  @Test func aBlankOrZeroEntryRemovesTheTimerAndItStaysRemoved() {
    var (draft, id) = stepDraft("Bake 25 minutes.")
    draft.setTimer(id, minutes: "")
    #expect(draft.steps[0].timerSeconds == nil)
    draft.setStepText(id, "Bake 30 minutes.")
    #expect(draft.steps[0].timerSeconds == nil)
    draft.setTimer(id, minutes: "10")
    draft.setTimer(id, minutes: "0")
    #expect(draft.steps[0].timerSeconds == nil)
  }

  @Test func aTimerIsHeldToTheLimitAndJunkLeavesItAlone() {
    var (draft, id) = stepDraft("Ferment.")
    draft.setTimer(id, minutes: "999999")
    #expect(draft.steps[0].timerSeconds == RecipeLimits.timerSeconds)
    draft.setTimer(id, minutes: "10")
    draft.setTimer(id, minutes: "ten")
    #expect(draft.steps[0].timerSeconds == 600)
  }

  @Test func aTimerRoundedToNothingIsAProblem() {
    var (draft, id) = stepDraft("Ferment.")
    draft.title = "Bread"
    draft.setTimer(id, minutes: "0.001")
    #expect(draft.steps[0].timerSeconds == 0)
    #expect(draft.validate()[.step(id)] != nil)
  }

  @Test func settingATimerOnAMissingStepDoesNothing() {
    var draft = RecipeDraft()
    draft.setTimer(UUID(), minutes: "5")
    #expect(draft.steps[0].timerSeconds == nil)
  }

  // MARK: When a problem shows

  @Test func problemsCanBeNarrowedToTheFieldsTheCookHasLeft() {
    var draft = RecipeDraft()
    draft.servings = "ten"
    draft.sourceURL = "not a url"
    let all = draft.validate()
    #expect(all[.title] != nil && all[.servings] != nil && all[.sourceURL] != nil)

    let shown = all.showing([.servings])
    #expect(shown[.servings] == all[.servings])
    #expect(shown[.title] == nil && shown[.sourceURL] == nil)
    #expect(all.showing([]).isEmpty)
    #expect(all.showing([.notes]).isEmpty)
  }

  // MARK: Views

  private func renders(_ view: some View) -> Bool {
    ImageRenderer(content: view.frame(width: 390, height: 800)).cgImage != nil
  }

  @Test func theFixFieldsAndTheTimerFieldRenderInBothAppearances() {
    var (draft, id) = draft(line: "1 1/2 cups (190g) flour, sifted")
    draft.setIngredientItem(id, "plain flour")
    let step = StepRowDraft.imported("Bake 25 minutes.", section: nil, flagged: false)
    for scheme in [ColorScheme.light, .dark] {
      for open in [false, true] {
        let fix = List {
          IngredientFixView(
            draft: .constant(draft), row: draft.ingredients[0], open: open, toggle: {})
        }
        .environment(\.colorScheme, scheme)
        #expect(renders(fix), "fix \(open) \(scheme)")
        let timer = List {
          StepTimerView(draft: .constant(draft), step: step, open: open, toggle: {})
        }
        .environment(\.colorScheme, scheme)
        #expect(renders(timer), "timer \(open) \(scheme)")
      }
    }
  }
}
