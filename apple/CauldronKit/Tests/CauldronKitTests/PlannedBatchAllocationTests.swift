import CauldronKit
import Testing

@Suite("Planned batch allocation")
struct PlannedBatchAllocationTests {
  @Test func allocationCountsConcreteServingsAndKeepsInvalidAssignmentsVisible() throws {
    let monday = try #require(LocalDate("2026-10-05"))
    let result = PlannedBatchAllocation(
      assignments: [
        .init(day: monday, servings: 2),
        .init(day: monday.adding(days: 8), servings: 5),
        .init(day: nil, servings: nil),
      ], weekStart: monday, total: 4, servingLimit: 40)
    #expect(result.assigned == 7)
    #expect(result.total == 4)
    #expect(result.unassigned == 0)
    #expect(result.isOverAssigned)
    #expect(result.hasInvalidEntries)
  }

  @Test func assignmentValidationRequiresSavedWeekAndConcreteBoundedServings() throws {
    let monday = try #require(LocalDate("2026-10-05"))
    #expect(
      PlannedBatchAllocation.accepts(
        day: monday.adding(days: 6), servings: 3, weekStart: monday, servingLimit: 40))
    #expect(
      !PlannedBatchAllocation.accepts(
        day: monday.adding(days: 7), servings: 3, weekStart: monday, servingLimit: 40))
    #expect(
      !PlannedBatchAllocation.accepts(
        day: monday, servings: 0, weekStart: monday, servingLimit: 40))
  }
}
