import CauldronKit
import SwiftData
import Testing

@testable import Cauldron

struct PlannedEntryEditingTests {
  @Test func batchEditingRequiresConcreteServingsWithinCapacityAndWeek() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let monday = try #require(LocalDate("2026-10-19"))
    let batch = PlannedBatchRecord(
      weekStart: monday, title: "Soup", totalServings: 6, ingredientYield: 6)
    let selected = PlanEntryRecord(day: monday, slot: .dinner, title: "Soup", servings: 2)
    selected.batch = batch
    let other = PlanEntryRecord(
      day: monday.adding(days: 1), slot: .dinner, title: "Soup", servings: 3)
    other.batch = batch
    context.insert(batch)
    context.insert(selected)
    context.insert(other)

    let limits = PlannedEntryLimits(batch: batch, entry: selected, records: [selected, other])

    #expect(limits.maxServings == 3)
    #expect(limits.allows(day: monday, servings: 3))
    #expect(!limits.allows(day: monday.adding(days: 7), servings: 1))
    #expect(!limits.allows(day: monday, servings: nil))
    #expect(!limits.allows(day: monday, servings: 4))
  }

  @Test func legacyEditingHasNoBatchRestrictions() throws {
    let monday = try #require(LocalDate("2026-10-19"))
    let limits: PlannedEntryLimits? = nil

    #expect(limits?.allows(day: monday.adding(days: 30), servings: nil) ?? true)
  }
}
