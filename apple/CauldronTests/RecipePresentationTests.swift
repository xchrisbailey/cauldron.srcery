import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Recipe presentation")
struct RecipePresentationTests {
  private func line(
    _ item: String, _ quantity: Double? = nil, _ unit: UnitCode? = nil, note: String? = nil,
    optional: Bool = false, section: String? = nil
  ) -> Ingredient {
    Ingredient(
      section: section, quantity: quantity.map { Quantity(min: $0, max: nil) }, unit: unit,
      item: item, note: note, optional: optional, alt: nil, original: item,
      itemKey: ingredientKey(item))
  }

  private func record(_ title: String = "Soup") throws -> RecipeRecord {
    let context = ModelContext(try CauldronStore.container(.inMemory))
    let record = RecipeRecord(title: title)
    context.insert(record)
    return record
  }

  // MARK: Ingredient rows

  @Test func ingredientsScaleAndKeepTheirUnit() {
    let rows = IngredientRow.rows(
      [line("flour", 1.5, .cup, note: "sifted"), line("salt")], factor: 2, system: .asWritten)
    #expect(
      rows == [
        .line(IngredientRow.Line(amount: "3", unit: "c", text: "flour, sifted", optional: false)),
        .line(IngredientRow.Line(amount: nil, unit: nil, text: "salt", optional: false)),
      ])
  }

  @Test func ingredientsConvertToTheChosenSystem() {
    let rows = IngredientRow.rows([line("flour", 1, .cup)], factor: 1, system: .metric)
    #expect(
      rows == [.line(IngredientRow.Line(amount: "235", unit: "ml", text: "flour", optional: false))]
    )
  }

  @Test func aHeadingComesBeforeEachNewSection() {
    let rows = IngredientRow.rows(
      [
        line("onion"),
        line("cream", section: "Sauce"),
        line("butter", section: "Sauce"),
        line("parsley", section: "To serve"),
      ], factor: 1, system: .asWritten)
    #expect(rows.count == 6)
    #expect(
      rows[0] == .line(IngredientRow.Line(amount: nil, unit: nil, text: "onion", optional: false)))
    #expect(rows[1] == .heading("Sauce"))
    #expect(rows[4] == .heading("To serve"))
  }

  @Test func optionalLinesAreMarked() {
    let rows = IngredientRow.rows([line("chili", optional: true)], factor: 1, system: .asWritten)
    #expect(
      rows == [.line(IngredientRow.Line(amount: nil, unit: nil, text: "chili", optional: true))])
  }

  // MARK: Card and facts

  @Test func aCardShowsTimeTagsAndTheMacroLine() throws {
    let recipe = try record()
    recipe.prepMinutes = 10
    recipe.cookMinutes = 25
    recipe.macros = Macros(calories: 310, protein: 17, carbs: 18, fat: 19)
    let context = try #require(recipe.modelContext)
    for name in ["Vegetarian", "Breakfast", "Quick"] {
      let tag = TagRecord(name: name, kind: name == "Breakfast" ? .meal : .other)
      context.insert(tag)
      recipe.tags = (recipe.tags ?? []) + [tag]
    }
    let card = RecipeCardInfo(recipe)
    #expect(card.title == "Soup")
    #expect(card.time == "35 min")
    #expect(card.tags.map(\.kind) == [.meal, .other])
    #expect(card.tags.map(\.name) == ["Breakfast", "Quick"])
    #expect(card.macros?.text == "310 kcal · 17P · 19F · 18C")
    #expect(card.macros?.label == "Per serving: 310 kcal, 17 g protein, 19 g fat, 18 g carbs")
  }

  @Test func aCardWithNothingKnownShowsOnlyItsTitle() throws {
    let card = RecipeCardInfo(try record())
    #expect(card.time == nil)
    #expect(card.tags.isEmpty)
    #expect(card.macros == nil)
  }

  @Test func totalMinutesBeatPrepPlusCook() throws {
    let recipe = try record()
    recipe.totalMinutes = 90
    recipe.prepMinutes = 10
    recipe.cookMinutes = 25
    let times = RecipeTimes(recipe)
    #expect(times.total == "1 h 30 min")
    #expect(times.prep == "10 min")
    #expect(times.cook == "25 min")
  }

  @Test func unknownAndZeroTimesAreLeftOut() throws {
    let recipe = try record()
    recipe.prepMinutes = 0
    let times = RecipeTimes(recipe)
    #expect(times.total == nil)
    #expect(times.prep == nil)
    #expect(times.cook == nil)
  }

  // MARK: Steps

  @Test func stepsAreNumberedAcrossSectionsWithTheirTimers() {
    let rows = StepRow.rows([
      Step(section: nil, text: "Chop.", timerSeconds: nil),
      Step(section: "Sauce", text: "Simmer.", timerSeconds: 600),
      Step(section: "Sauce", text: "Season.", timerSeconds: 90),
    ])
    #expect(
      rows == [
        .step(number: 1, text: "Chop.", timer: nil),
        .heading("Sauce"),
        .step(number: 2, text: "Simmer.", timer: "10 min"),
        .step(number: 3, text: "Season.", timer: "1 min 30 s"),
      ])
  }

  // MARK: Scale and source

  @Test func theScaleReadsAsServingsOrAMultiplier() {
    #expect(RecipeScale.label(.servings(6)) == "serves 6")
    #expect(RecipeScale.label(.multiplier(1.5)) == "×1 ½")
    #expect(RecipeScale.label(.multiplier(2)) == "×2")
  }

  @Test func theSourceShowsItsHostAndOnlyWebLinksOpen() {
    #expect(RecipeSource.host("https://www.example.com/a/b") == "example.com")
    #expect(RecipeSource.host("not a link") == "not a link")
    #expect(RecipeSource.link("https://example.com/a")?.absoluteString == "https://example.com/a")
    #expect(RecipeSource.link("javascript:alert(1)") == nil)
    #expect(RecipeSource.link("not a link") == nil)
  }

  @Test func lastCookedIsAShortDate() throws {
    let day = try #require(LocalDate("2026-10-01"))
    #expect(RecipeDates.short(day, locale: Locale(identifier: "en_US")) == "Oct 1")
  }
}
