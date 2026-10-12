import CauldronKit
import Foundation
import SwiftData
import Testing

@testable import Cauldron

@MainActor
@Suite("Recipe cooking")
struct RecipeCookingTests {
  private let context: ModelContext

  init() throws {
    context = ModelContext(try CauldronStore.container(.inMemory))
  }

  private func recipe() -> RecipeRecord {
    let record = RecipeRecord(title: "Soup")
    context.insert(record)
    return record
  }

  private func day(_ key: String) throws -> LocalDate { try #require(LocalDate(key)) }

  private func cooks(_ recipe: RecipeRecord) -> [String] {
    (recipe.cooks ?? []).map(\.cookedOnKey).sorted()
  }

  @Test func cookingARecipeRecordsTheDayAndSetsWhenItWasLastCooked() throws {
    let soup = recipe()
    try RecipeCooking.markCooked(soup, on: day("2026-10-11"), context: context)
    #expect(cooks(soup) == ["2026-10-11"])
    #expect(soup.lastCookedOn == LocalDate("2026-10-11"))
  }

  @Test func cookingItTwiceOnOneDayIsOneEntry() throws {
    let soup = recipe()
    try RecipeCooking.markCooked(soup, on: day("2026-10-11"), context: context)
    try RecipeCooking.markCooked(soup, on: day("2026-10-11"), context: context)
    #expect(cooks(soup) == ["2026-10-11"])
    #expect(try context.fetchCount(FetchDescriptor<CookRecord>()) == 1)
  }

  @Test func anEarlierDayIsRecordedButNeverMovesLastCookedBack() throws {
    let soup = recipe()
    try RecipeCooking.markCooked(soup, on: day("2026-10-11"), context: context)
    try RecipeCooking.markCooked(soup, on: day("2026-10-01"), context: context)
    #expect(cooks(soup) == ["2026-10-01", "2026-10-11"])
    #expect(soup.lastCookedOn == LocalDate("2026-10-11"))
    try RecipeCooking.markCooked(soup, on: day("2026-10-20"), context: context)
    #expect(soup.lastCookedOn == LocalDate("2026-10-20"))
  }

  @Test func otherRecipesAreNotTouched() throws {
    let soup = recipe()
    let stew = recipe()
    try RecipeCooking.markCooked(soup, on: day("2026-10-11"), context: context)
    #expect(cooks(stew).isEmpty)
    #expect(stew.lastCookedOn == nil)
  }

  @Test func theChangeIsSavedAndStamped() throws {
    let soup = recipe()
    soup.updatedAt = Date(timeIntervalSince1970: 0)
    let now = Date(timeIntervalSince1970: 9_000)
    try RecipeCooking.markCooked(soup, on: day("2026-10-11"), context: context, now: now)
    #expect(soup.updatedAt == now)
    #expect(!context.hasChanges)
  }

  @Test func todayIsTheCooksOwnCalendarDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
    // 2026-10-11 20:00 UTC is already the 12th in Auckland.
    let instant = Date(timeIntervalSince1970: 1_791_748_800)
    #expect(RecipeCooking.today(now: instant, calendar: calendar) == LocalDate("2026-10-12"))
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    #expect(RecipeCooking.today(now: instant, calendar: calendar) == LocalDate("2026-10-11"))
  }
}
