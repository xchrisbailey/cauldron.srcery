import CauldronKit
import Foundation
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

  @Test @MainActor func legacyEditingStillAllowsNilServingsAndDatesOutsideAWeek() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let monday = try #require(LocalDate("2026-10-19"))
    let outsideWeek = monday.adding(days: 30)
    let entry = PlanEntryRecord(day: monday, slot: .dinner, title: "Leftovers", servings: 2)
    context.insert(entry)

    var change = EntryChange()
    change.day = outsideWeek
    change.servings = .some(nil)
    try WeekPlan.apply(change, to: entry, in: context)

    #expect(entry.day == outsideWeek)
    #expect(entry.servings == nil)
    #expect(entry.batch == nil)
  }

  @Test @MainActor func staleUntouchedBatchDraftCannotRestoreOldCapacityOnAssignment() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let monday = try #require(LocalDate("2026-10-19"))
    let recipe = RecipeRecord(title: "Soup")
    let batch = PlannedBatchRecord(
      weekStart: monday, title: "Soup", totalServings: 4, ingredientYield: 4)
    batch.recipe = recipe
    let existing = PlanEntryRecord(day: monday, slot: .dinner, title: "Soup", servings: 1)
    existing.batch = batch
    context.insert(recipe)
    context.insert(batch)
    context.insert(existing)
    var draft = PlannedBatchEditDraft(openedTotal: 4)

    batch.totalServings = 2
    #expect(try draft.totalToCommit(currentTotal: batch.totalServings) == nil)
    #expect(throws: WeekPlanError.batchOverAssigned) {
      try draft.assign(3, on: monday.adding(days: 1), slot: .dinner, to: batch, in: context)
    }
    #expect(batch.totalServings == 2)
    #expect((batch.entries ?? []).count == 1)
  }

  @Test @MainActor func untouchedBatchDraftUsesSyncedTotalForConflictRepairSaveEligibility() throws
  {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let monday = try #require(LocalDate("2026-10-19"))
    let batch = PlannedBatchRecord(
      weekStart: monday, title: "Soup", totalServings: 4, ingredientYield: 4)
    for dayOffset in 0..<2 {
      let entry = PlanEntryRecord(
        day: monday.adding(days: dayOffset), slot: .dinner, title: "Soup", servings: 3)
      entry.batch = batch
      context.insert(entry)
    }
    context.insert(batch)
    try context.save()
    let batchID = batch.id
    let draft = PlannedBatchEditDraft(openedTotal: 4)

    #expect(WeekPlan.allocation(batch).isOverAssigned)
    #expect(!draft.canSave(currentTotal: batch.totalServings, assigned: 6))

    batch.totalServings = 6
    try context.save()
    let refreshedContext = ModelContext(container)
    let refreshedBatch = try #require(
      refreshedContext.fetch(
        FetchDescriptor<PlannedBatchRecord>(predicate: #Predicate { $0.id == batchID })
      ).first)
    let allocation = WeekPlan.allocation(refreshedBatch)

    #expect(!allocation.isOverAssigned)
    #expect(draft.effectiveTotal(currentTotal: refreshedBatch.totalServings) == 6)
    #expect(
      draft.canSave(currentTotal: refreshedBatch.totalServings, assigned: allocation.assigned))
    #expect(try draft.totalToCommit(currentTotal: refreshedBatch.totalServings) == nil)
    var explicitDraft = PlannedBatchEditDraft(openedTotal: 4)
    explicitDraft.setTotal(5)
    #expect(explicitDraft.effectiveTotal(currentTotal: refreshedBatch.totalServings) == 5)
    #expect(!explicitDraft.canSave(currentTotal: refreshedBatch.totalServings, assigned: 6))
  }

  @Test @MainActor func explicitCapacityIncreaseAndAssignmentCommitAsOneChange() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let monday = try #require(LocalDate("2026-10-19"))
    let recipe = RecipeRecord(title: "Soup")
    let batch = PlannedBatchRecord(
      weekStart: monday, title: "Soup", totalServings: 4, ingredientYield: 4)
    batch.recipe = recipe
    let existing = PlanEntryRecord(day: monday, slot: .dinner, title: "Soup", servings: 1)
    existing.batch = batch
    context.insert(recipe)
    context.insert(batch)
    context.insert(existing)
    let batchDraft = PlannedBatchEditDraft(openedTotal: 4)
    var draft = batchDraft
    draft.setTotal(5)
    try draft.assign(2, on: monday.adding(days: 1), slot: .lunch, to: batch, in: context)

    #expect(batch.totalServings == 5)
    #expect(WeekPlan.allocation(batch).assigned == 3)
    #expect(WeekPlan.allocation(batch).unassigned == 2)
  }

  @Test @MainActor func explicitCapacityIncreaseAndAssignmentRollBackTogetherOnFullSlot() throws {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let monday = try #require(LocalDate("2026-10-19"))
    let recipe = RecipeRecord(title: "Soup")
    let batch = PlannedBatchRecord(
      weekStart: monday, title: "Soup", totalServings: 1, ingredientYield: 1)
    batch.recipe = recipe
    context.insert(recipe)
    context.insert(batch)
    for index in 0..<WeekLimits.perSlot {
      context.insert(
        PlanEntryRecord(day: monday, slot: .dinner, title: "Meal \(index)", servings: 1))
    }
    try context.save()
    let batchID = batch.id
    var draft = PlannedBatchEditDraft(openedTotal: 1)
    draft.setTotal(2)
    #expect(draft.availableServings(currentTotal: 1, assigned: 0) == 2)

    #expect(throws: WeekPlanError.slotFull) {
      try draft.assign(1, on: monday, slot: .dinner, to: batch, in: context)
    }
    #expect(batch.totalServings == 1)
    let refreshed = ModelContext(container)
    let stored = try #require(
      refreshed.fetch(
        FetchDescriptor<PlannedBatchRecord>(predicate: #Predicate { $0.id == batchID })
      ).first)
    #expect(stored.totalServings == 1)
    #expect((stored.entries ?? []).isEmpty)
  }

  @Test @MainActor func purgedRecipeBatchEntryWithUnreadableDateAndNilServingsCanBeRepaired() throws
  {
    let container = try CauldronStore.container(.inMemory)
    let context = ModelContext(container)
    let monday = try #require(LocalDate("2026-10-19"))
    let batch = PlannedBatchRecord(
      weekStart: monday, title: "Soup", totalServings: 3, ingredientYield: 3)
    let entry = PlanEntryRecord(day: monday, slot: .dinner, title: "Soup", servings: nil)
    entry.dayKey = "unreadable"
    entry.batch = batch
    context.insert(batch)
    context.insert(entry)
    var change = EntryChange()
    change.day = monday.adding(days: 1)
    change.slot = .lunch
    change.servings = .some(2)

    try WeekPlan.commit(in: context) { try WeekPlan.apply(change, to: entry, in: context) }

    #expect(entry.day == monday.adding(days: 1))
    #expect(entry.slot == .lunch)
    #expect(entry.servings == 2)
    #expect(entry.batch === batch && batch.recipe == nil)
    #expect(WeekPlan.allocation(batch).assigned == 2)
    #expect(!WeekPlan.allocation(batch).hasInvalidEntries)
  }
}
