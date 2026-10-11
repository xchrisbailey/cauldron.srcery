import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Recipe library")
struct RecipeLibraryTests {
  private let context: ModelContext

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  @discardableResult
  private func recipe(
    _ title: String, items: [String] = [], tags: [String] = [], created: TimeInterval = 0,
    cooked: String? = nil, banished: Bool = false
  ) -> RecipeRecord {
    let record = RecipeRecord(title: title)
    context.insert(record)
    record.ingredients = items.map {
      Ingredient(
        section: nil, quantity: nil, unit: nil, item: $0, note: nil, optional: false, alt: nil,
        original: $0, itemKey: ingredientKey($0))
    }
    record.tags = tags.map {
      let tag = TagRecord(name: $0)
      context.insert(tag)
      return tag
    }
    record.createdAt = Date(timeIntervalSince1970: created)
    record.lastCookedOn = cooked.flatMap { LocalDate($0) }
    if banished { record.deletedAt = .now }
    record.refreshSearchText()
    return record
  }

  private func titles(
    _ recipes: [RecipeRecord], matching query: String = "", sort: RecipeSort = .recent
  ) -> [String] {
    RecipeLibrary.visible(recipes, matching: query, sort: sort).map(\.title)
  }

  // MARK: Search

  @Test func aBlankSearchKeepsEveryRecipe() {
    let all = [recipe("Soup"), recipe("Cookies", created: 1)]
    #expect(Set(titles(all, matching: "   ")) == ["Soup", "Cookies"])
  }

  @Test func searchMatchesTitleIngredientAndTagAnyCase() {
    let all = [
      recipe("Shakshuka", items: ["feta"]),
      recipe("Oats", tags: ["Breakfast"]),
      recipe("Soup", items: ["white beans"]),
    ]
    #expect(titles(all, matching: "SHAK") == ["Shakshuka"])
    #expect(titles(all, matching: "feta") == ["Shakshuka"])
    #expect(titles(all, matching: "breakfast") == ["Oats"])
    #expect(titles(all, matching: "beans") == ["Soup"])
    #expect(titles(all, matching: "nothing at all").isEmpty)
  }

  @Test func everyWordOfASearchHasToMatch() {
    let all = [recipe("Tomato soup", items: ["basil"]), recipe("Tomato salad")]
    #expect(titles(all, matching: "tomato basil") == ["Tomato soup"])
    #expect(titles(all, matching: " basil  tomato ") == ["Tomato soup"])
  }

  @Test func banishedRecipesAreHiddenFromTheListAndSearch() {
    let all = [recipe("Soup"), recipe("Stew", banished: true)]
    #expect(titles(all) == ["Soup"])
    #expect(titles(all, matching: "stew").isEmpty)
  }

  @Test func banishingHidesTheRecipeButKeepsItsRow() throws {
    let soup = recipe("Soup")
    let stew = recipe("Stew")
    let now = Date(timeIntervalSince1970: 1_000)
    RecipeLibrary.banish(soup, at: now)
    #expect(soup.deletedAt == now)
    #expect(titles([soup, stew]) == ["Stew"])
    #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 2)
  }

  @Test func banishingTwiceKeepsTheFirstTime() {
    let soup = recipe("Soup")
    RecipeLibrary.banish(soup, at: Date(timeIntervalSince1970: 1_000))
    RecipeLibrary.banish(soup, at: Date(timeIntervalSince1970: 2_000))
    #expect(soup.deletedAt == Date(timeIntervalSince1970: 1_000))
  }

  // MARK: Sort

  @Test func newestFirstUsesTheCreatedDate() {
    let all = [recipe("Old", created: 1), recipe("New", created: 9), recipe("Mid", created: 5)]
    #expect(titles(all, sort: .recent) == ["New", "Mid", "Old"])
  }

  @Test func titleSortIgnoresCase() {
    let all = [recipe("banana bread"), recipe("Apple pie"), recipe("Cookies")]
    #expect(titles(all, sort: .title) == ["Apple pie", "banana bread", "Cookies"])
  }

  @Test func lastCookedPutsTheLatestFirstAndNeverCookedLastByTitle() {
    let all = [
      recipe("Never too"),
      recipe("Spring", cooked: "2026-04-01"),
      recipe("Autumn", cooked: "2026-10-01"),
      recipe("Never"),
    ]
    #expect(titles(all, sort: .lastCooked) == ["Autumn", "Spring", "Never", "Never too"])
  }

  @Test func equalSortKeysFallBackToTitleSoTheOrderIsStable() {
    let all = [recipe("B", created: 4), recipe("A", created: 4)]
    #expect(titles(all, sort: .recent) == ["A", "B"])
  }

  @Test func sortsReadTheirNamesFromTheCopyModule() {
    #expect(RecipeSort.allCases.map(\.label.text) == ["Newest", "A to Z", "Last cooked"])
  }
}
