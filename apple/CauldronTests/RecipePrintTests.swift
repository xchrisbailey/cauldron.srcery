import CauldronKit
import CoreText
import Foundation
import PDFKit
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

/// What a printed recipe says, and that it comes out as a PDF.
@MainActor
@Suite("Printing a recipe")
struct RecipePrintTests {
  private let context: ModelContext

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  private func line(_ original: String, section: String? = nil) -> Ingredient {
    let parsed = parseIngredientLine(original)
    return Ingredient(
      section: section, quantity: parsed.quantity, unit: parsed.unit, item: parsed.item,
      note: parsed.note, optional: parsed.optional, alt: nil, original: original,
      itemKey: ingredientKey(parsed.item))
  }

  private func soup(steps: Int = 2) -> RecipeRecord {
    let recipe = RecipeRecord(title: "Red lentil dal")
    context.insert(recipe)
    recipe.summary = "Comfort in a bowl."
    recipe.servings = 4
    recipe.prepMinutes = 10
    recipe.cookMinutes = 25
    recipe.sourceURL = "https://www.example.com/dal"
    recipe.sourceAuthor = "Ada"
    recipe.ingredients = [
      line("1 cup red lentils"), line("2 tbsp butter", section: "To finish"),
      line("salt, optional"),
    ]
    recipe.steps = (1...steps).map {
      Step(
        section: nil, text: "Step \($0): simmer the lentils gently.",
        timerSeconds: $0 == 1 ? 600 : nil)
    }
    recipe.notes = "Keeps for three days."
    return recipe
  }

  // MARK: Content

  @Test func theTitleServingsTimesAndSourceAreThere() {
    let printout = RecipePrintout(soup(), scale: .servings(4), units: .asWritten)
    #expect(printout.title == "Red lentil dal")
    #expect(printout.summary == "Comfort in a bowl.")
    #expect(printout.facts == ["serves 4", "35 min", "10 min prep", "25 min cook"])
    #expect(printout.source == "From example.com · by Ada")
    #expect(printout.notes == "Keeps for three days.")
  }

  @Test func servingsAndIngredientsFollowTheScaleOnScreen() throws {
    let recipe = soup()
    let doubled = RecipePrintout(recipe, scale: .servings(8), units: .asWritten)
    #expect(doubled.facts.first == "serves 8")
    let rows = doubled.ingredients.compactMap { row -> IngredientRow.Line? in
      if case .line(let line) = row { line } else { nil }
    }
    #expect(rows.first?.amount == "2")
    #expect(rows.first?.unit == "c")
  }

  @Test func ingredientsFollowTheUnitSystemChosen() throws {
    let recipe = soup()
    let written = RecipePrintout(recipe, scale: .servings(4), units: .asWritten)
    let metric = RecipePrintout(recipe, scale: .servings(4), units: .metric)
    #expect(written.ingredients != metric.ingredients)
    let first = metric.ingredients.compactMap { row -> IngredientRow.Line? in
      if case .line(let line) = row { line } else { nil }
    }.first
    #expect(first?.unit == "ml" || first?.unit == "g")
  }

  @Test func aRecipeWithNoServingsPrintsItsMultiplier() {
    let recipe = soup()
    recipe.servings = nil
    let printout = RecipePrintout(recipe, scale: .multiplier(1.5), units: .asWritten)
    #expect(printout.facts.first == RecipeScale.label(.multiplier(1.5)))
  }

  @Test func aBareRecipeHasNoSourceNotesOrFacts() {
    let recipe = RecipeRecord(title: "Toast")
    context.insert(recipe)
    let printout = RecipePrintout(recipe, scale: .multiplier(1), units: .asWritten)
    #expect(printout.source == nil)
    #expect(printout.notes == nil)
    #expect(printout.summary == nil)
    #expect(printout.ingredients.isEmpty && printout.steps.isEmpty)
  }

  @Test func theFileNameIsTheTitleWithoutPathCharacters() {
    let recipe = RecipeRecord(title: "Mac / cheese: the best?")
    context.insert(recipe)
    let name = RecipePrintout(recipe, scale: .multiplier(1), units: .asWritten).fileName
    #expect(name == "Mac   cheese  the best.pdf")
    let untitled = RecipeRecord(title: "")
    context.insert(untitled)
    #expect(
      RecipePrintout(untitled, scale: .multiplier(1), units: .asWritten).fileName
        == Copy.pageTitles.recipe.text + ".pdf")
  }

  // MARK: The PDF

  private func document(_ printout: RecipePrintout) throws -> PDFDocument {
    try #require(PDFDocument(data: RecipePDF.render(printout)))
  }

  @Test func theRecipeComesOutAsAPDFThatSaysWhatThePageSays() throws {
    let printout = RecipePrintout(soup(), scale: .servings(4), units: .asWritten)
    let pdf = try document(printout)
    #expect(pdf.pageCount == 1)
    let text = pdf.string ?? ""
    for expected in [
      "Red lentil dal", "serves 4", "red lentils", "butter", "To finish", "simmer the lentils",
      "Keeps for three days.", "From example.com", Copy.recipeView.ingredients.text.uppercased(),
      Copy.recipeView.method.text.uppercased(),
    ] {
      #expect(text.contains(expected), "\(expected) is on the page")
    }
  }

  @Test func theOptionalMarkIsPrinted() throws {
    let printout = RecipePrintout(soup(), scale: .servings(4), units: .asWritten)
    let text = try document(printout).string ?? ""
    #expect(text.contains("(\(Copy.recipeView.optional.text))"))
  }

  @Test func aLongRecipeRunsOntoMorePagesWithoutLosingAStep() throws {
    let printout = RecipePrintout(soup(steps: 120), scale: .servings(4), units: .asWritten)
    let pdf = try document(printout)
    #expect(pdf.pageCount > 1)
    let text = pdf.string ?? ""
    #expect(text.contains("Step 1:") && text.contains("Step 120:"))
  }

  @Test func thePageIsLetterOrA4() {
    #expect(
      RecipePDF.pageSize(locale: Locale(identifier: "en_US")) == CGSize(width: 612, height: 792))
    #expect(
      RecipePDF.pageSize(locale: Locale(identifier: "en_GB")) == CGSize(width: 595, height: 842))
  }

  @Test func thePaperUsesTheLatteColoursWhateverTheAppearance() throws {
    let printout = RecipePrintout(soup(), scale: .servings(4), units: .asWritten)
    let text = RecipePDF.attributedText(for: printout)
    // The title is the first run; its colour is Latte's ink (0x4C4F69) rather than Mocha's.
    let attributes = text.attributes(at: 0, effectiveRange: nil)
    let color = try #require(
      attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)]
    )
    let cgColor = color as! CGColor
    let components = try #require(cgColor.components)
    #expect(abs(components[0] - CGFloat(0x4C) / 255) < 0.01)
    #expect(abs(components[1] - CGFloat(0x4F) / 255) < 0.01)
    #expect(abs(components[2] - CGFloat(0x69) / 255) < 0.01)
  }
}
