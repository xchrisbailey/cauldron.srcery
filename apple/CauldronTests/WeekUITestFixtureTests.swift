#if DEBUG
  import CauldronKit
  import SwiftData
  import Testing

  @testable import Cauldron

  @MainActor
  struct WeekUITestFixtureTests {
    @Test func fixtureRequiresBothIsolatedModeAndExplicitUITestContract() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = container.mainContext
      let selection = ["CAULDRON_UI_TEST_WEEK": "breakfast"]
      try WeekUITestFixture.populateIfRequested(
        mode: .inMemory, context: context, environment: selection)
      for mode in [CauldronStore.Mode.local, .synced] {
        try WeekUITestFixture.populateIfRequested(
          mode: mode, context: context,
          environment: selection.merging([CauldronStore.uiTestInMemoryEnvironmentKey: "1"]) {
            _, new in new
          })
      }
      #expect(try context.fetchCount(FetchDescriptor<PlannedBatchRecord>()) == 0)
      #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 0)
      #expect(try context.fetchCount(FetchDescriptor<TargetsRecord>()) == 0)
    }

    @Test(arguments: ["breakfast", "dinner"])
    func populatedFixtureHasIndependentDuplicateBatchesAndTwoUnassignedServings(scenario: String)
      throws
    {
      let container = try CauldronStore.container(.inMemory)
      let context = container.mainContext
      try WeekUITestFixture.populateIfRequested(
        mode: .inMemory, context: context,
        environment: [
          CauldronStore.uiTestInMemoryEnvironmentKey: "1", "CAULDRON_UI_TEST_WEEK": scenario,
        ])
      let batches = try context.fetch(FetchDescriptor<PlannedBatchRecord>())
      let entries = try context.fetch(FetchDescriptor<PlanEntryRecord>())
      #expect(batches.count == 7)
      #expect(Set(batches.map(\.id)).count == 7)
      #expect(Set(batches.compactMap { $0.recipe?.id }).count == 6)
      #expect(batches.reduce(0) { $0 + WeekPlan.allocation($1).unassigned } == 2)
      #expect(entries.count == 7)
      #expect(entries.allSatisfy { $0.slot == (scenario == "dinner" ? .dinner : .breakfast) })
      #expect(try context.fetchCount(FetchDescriptor<TargetsRecord>()) == 1)
    }
  }
#endif
