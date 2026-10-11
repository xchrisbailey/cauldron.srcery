import CauldronKit
import Foundation
import Testing

@testable import Cauldron

@MainActor
@Suite("Recipe draft validation")
struct RecipeDraftValidationTests {
  private func valid() -> RecipeDraft {
    var draft = RecipeDraft()
    draft.title = "Soup"
    return draft
  }

  private func message(_ field: RecipeDraft.Field, in draft: RecipeDraft) -> String? {
    draft.validate()[field]?.text
  }

  @Test func aTitledRecipeWithNothingElseIsValid() {
    #expect(valid().validate().isEmpty)
  }

  @Test func aBlankTitleNeedsFillingIn() {
    var draft = valid()
    draft.title = "   "
    #expect(message(.title, in: draft) == Copy.validation.required.text)
    #expect(!draft.validate().isEmpty)
  }

  @Test func textLongerThanTheLimitSaysHowLongItCanBe() {
    var draft = valid()
    draft.title = String(repeating: "a", count: RecipeLimits.title + 1)
    draft.summary = String(repeating: "a", count: RecipeLimits.description + 1)
    draft.notes = String(repeating: "a", count: RecipeLimits.notes + 1)
    #expect(message(.title, in: draft) == "Keep it to 200 characters or fewer.")
    #expect(message(.summary, in: draft) == "Keep it to 2000 characters or fewer.")
    #expect(message(.notes, in: draft) == "Keep it to 20000 characters or fewer.")
    draft.title = String(repeating: "a", count: RecipeLimits.title)
    #expect(message(.title, in: draft) == nil)
  }

  @Test func servingsAndTimesAreWholeNumbersInRange() {
    var draft = valid()
    draft.servings = "0"
    draft.prepMinutes = "-1"
    draft.cookMinutes = "ten"
    draft.totalMinutes = "2.5"
    #expect(message(.servings, in: draft) == "Use a whole number from 1 to 1000.")
    #expect(message(.prepMinutes, in: draft) == "Use a whole number from 0 to 20160.")
    #expect(message(.cookMinutes, in: draft) == "Use a whole number from 0 to 20160.")
    #expect(message(.totalMinutes, in: draft) == "Use a whole number from 0 to 20160.")

    draft.servings = "1000"
    draft.prepMinutes = "0"
    draft.cookMinutes = " 20160 "
    draft.totalMinutes = ""
    #expect(draft.validate().isEmpty)
    draft.servings = "1001"
    #expect(message(.servings, in: draft) != nil)
  }

  @Test func macrosAreNumbersInRangeAndCaloriesAreWhole() {
    var draft = valid()
    draft.calories = "310.5"
    draft.protein = "2001"
    draft.carbs = "abc"
    draft.fat = "-1"
    #expect(message(.calories, in: draft) == "Use a whole number from 0 to 20000.")
    #expect(message(.protein, in: draft) == "Use a number from 0 to 2000.")
    #expect(message(.carbs, in: draft) == "Use a number from 0 to 2000.")
    #expect(message(.fat, in: draft) == "Use a number from 0 to 2000.")

    draft.calories = "310"
    draft.protein = "12.5"
    draft.carbs = "0"
    draft.fat = "inf"
    #expect(message(.fat, in: draft) != nil)
    draft.fat = ""
    #expect(draft.validate().isEmpty)
  }

  @Test func theSourceLinkIsBlankOrAWebLink() {
    var draft = valid()
    for bad in [
      "example.com", "ftp://example.com", "https://", "https:// spaced.com", "javascript:x",
    ] {
      draft.sourceURL = bad
      #expect(message(.sourceURL, in: draft) == Copy.validation.link.text, "\(bad)")
    }
    for good in ["", "  ", "https://example.com", "HTTP://Example.com/a?b=c", " https://x.org/y "] {
      draft.sourceURL = good
      #expect(message(.sourceURL, in: draft) == nil, "\(good)")
    }
    draft.sourceURL = "https://example.com/" + String(repeating: "a", count: RecipeLimits.url)
    #expect(message(.sourceURL, in: draft) == "Keep it to 2048 characters or fewer.")
  }

  @Test func tagsHaveALengthAndACount() {
    var draft = valid()
    draft.tags = [String(repeating: "a", count: RecipeLimits.tag + 1)]
    #expect(message(.tags, in: draft) == "Keep it to 40 characters or fewer.")
    draft.tags = (0..<(RecipeLimits.tags + 1)).map { "tag\($0)" }
    #expect(message(.tags, in: draft) == "Use 30 or fewer.")
    draft.tags = (0..<RecipeLimits.tags).map { "tag\($0)" }
    #expect(message(.tags, in: draft) == nil)
  }

  @Test func aStoredLineWithNoItemIsMissingItsIngredient() {
    var draft = valid()
    let stored = Ingredient(
      section: nil, quantity: Quantity(min: 2, max: nil), unit: .cup, item: "", note: nil,
      optional: false, alt: nil, original: "2 cups", itemKey: "")
    draft.ingredients = [.stored(stored)]
    #expect(
      message(.ingredient(draft.ingredients[0].id), in: draft) == Copy.validation.required.text)
  }

  @Test func aStoredLineWithABackwardsRangeSaysSo() {
    var draft = valid()
    let stored = Ingredient(
      section: nil, quantity: Quantity(min: 3, max: 2), unit: .cup, item: "flour", note: nil,
      optional: false, alt: nil, original: "3-2 cups flour", itemKey: "flour")
    draft.ingredients = [.stored(stored)]
    #expect(message(.ingredient(draft.ingredients[0].id), in: draft) == Copy.validation.range.text)
  }

  @Test func blankLinesAndStepsAreIgnored() {
    var draft = valid()
    draft.addIngredient()
    draft.addStep()
    #expect(draft.validate().isEmpty)
  }

  @Test func aLineOrNoteOrHeadingThatIsTooLongIsFlaggedOnItsRow() {
    var draft = valid()
    let line = draft.ingredients[0].id
    draft.setIngredientText(line, String(repeating: "a", count: RecipeLimits.line + 1))
    #expect(message(.ingredient(line), in: draft) != nil)
    draft.addHeading(after: line)
    let heading = draft.ingredients[1].id
    draft.setIngredientText(heading, String(repeating: "h", count: RecipeLimits.section + 1))
    #expect(message(.ingredient(heading), in: draft) == "Keep it to 200 characters or fewer.")
  }

  @Test func tooManyIngredientsAreFlaggedOnTheList() {
    var draft = valid()
    draft.ingredients = (0...RecipeLimits.ingredients).map { .line("item \($0)") }
    #expect(message(.ingredientList, in: draft) == "Use 300 or fewer.")
  }

  @Test func aStepThatIsTooLongOrHasAnOutOfRangeTimerIsFlagged() {
    var draft = valid()
    let id = draft.steps[0].id
    draft.setStepText(id, String(repeating: "a", count: RecipeLimits.step + 1))
    #expect(message(.step(id), in: draft) == "Keep it to 5000 characters or fewer.")
    draft.setStepText(id, "Wait 80 hours.")
    // Over 72 hours is no timer at all, so the text is fine.
    #expect(draft.steps[0].timerSeconds == nil)
    #expect(message(.step(id), in: draft) == nil)
  }

  @Test func tooManyStepsAreFlaggedOnTheList() {
    var draft = valid()
    draft.steps = (0...RecipeLimits.steps).map {
      var step = StepRowDraft.blank()
      step.setText("step \($0)")
      return step
    }
    #expect(message(.stepList, in: draft) == "Use 200 or fewer.")
  }

  @Test func aLockedListIsNotCheckedBecauseItIsNotSaved() {
    var draft = valid()
    draft.ingredientsLocked = true
    draft.ingredients = (0...RecipeLimits.ingredients).map { .line("item \($0)") }
    #expect(draft.validate().isEmpty)
  }

  @Test func errorsKeepEachMessageAPlainCopyString() {
    var draft = valid()
    draft.title = ""
    #expect(draft.validate()[.title]?.tone == .plain)
  }
}
