import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

#if DEBUG
  @MainActor
  @Suite("Week views")
  struct WeekViewsTests {
    private func seeded() throws -> ModelContainer {
      let container = try CauldronStore.container(.inMemory)
      try DebugSeed.populate(ModelContext(container), today: DebugSeed.today())
      return container
    }

    private func renders(_ view: some View, width: CGFloat, height: CGFloat) -> Bool {
      ImageRenderer(content: view.frame(width: width, height: height)).cgImage != nil
    }

    @Test func theWeekRendersEmptyAndSeededInBothAppearancesAtEverySize() throws {
      let empty = try CauldronStore.container(.inMemory)
      let full = try seeded()
      for container in [empty, full] {
        for scheme in [ColorScheme.light, .dark] {
          for (width, height) in [(1100.0, 800.0), (390.0, 800.0)] {
            let view = WeekRoot().modelContainer(container).environment(\.colorScheme, scheme)
            #expect(renders(view, width: width, height: height), "\(scheme) \(width)")
          }
        }
      }
    }

    @Test func weekPlannerAndTargetSetupRenderAtBothWidthsAndAppearances() throws {
      let start = LocalDate("2026-10-05")!
      for hasTargets in [false, true] {
        let container = try CauldronStore.container(.inMemory)
        let context = ModelContext(container)
        if hasTargets {
          context.insert(TargetsRecord(calories: 2_000, protein: 100, carbs: 200, fat: 70))
          try context.save()
        }
        let planner = WeekPlanner(
          start: start, today: start, startsOn: .monday, isCurrent: true, onPrevious: {},
          onNext: {}, onThisWeek: {}, onStartsOn: { _ in })
        for scheme in [ColorScheme.light, .dark] {
          for width in [1_100.0, 390.0] {
            let height = 1_200.0
            let plannerView = planner.modelContainer(container).environment(\.colorScheme, scheme)
            #expect(
              renders(plannerView, width: width, height: height),
              "targets \(hasTargets), \(scheme), \(width)")
          }
          #expect(
            renders(
              TargetsView(context: context).modelContainer(container)
                .environment(\.colorScheme, scheme), width: 390, height: 760),
            "target setup \(scheme)")
        }
      }
    }

    @Test func simultaneousDailyAndWeeklyComparisonsRenderAtBothWidthsAndAppearances() {
      let start = LocalDate("2026-10-05")!
      let targets = TargetsRecord(calories: 2_000, protein: 100, carbs: 200, fat: 70)
      let snapshot = WeekSnapshot(start: start, records: [], targets: targets)
      let summary = WeekTallyView(snapshot: snapshot, day: start, onClearDay: {}, onOpenTargets: {})
      for scheme in [ColorScheme.light, .dark] {
        for (width, height) in [(1100.0, 800.0), (390.0, 800.0)] {
          #expect(
            renders(summary.environment(\.colorScheme, scheme), width: width, height: height),
            "daily and weekly comparison \(scheme) \(width)")
        }
      }
    }

    @Test func theStirSheetsRenderInBothAppearances() throws {
      let container = try seeded()
      let context = ModelContext(container)
      let recipes = try context.fetch(FetchDescriptor<RecipeRecord>())
      let recipe = try #require(recipes.first)
      let today = try DebugSeed.today()
      let target = MealTarget(day: today, slot: .dinner)
      for scheme in [ColorScheme.light, .dark] {
        let flow = StirFlowSheet(target: target, days: today.weekDays(), today: today) { _ in }
        #expect(
          renders(
            flow.modelContainer(container).environment(\.colorScheme, scheme), width: 420,
            height: 640))
        // A batch spread over several days, and a recipe of one serving.
        for scale in [Scale.servings(6), .servings(1)] {
          let recipePage = StirRecipeSheet(recipe: recipe, scale: scale, today: today) { _ in }
          #expect(
            renders(
              recipePage.modelContainer(container).environment(\.colorScheme, scheme), width: 420,
              height: 900))
        }
      }
    }

    @Test func theDroppedRecipeSheetRendersInBothAppearances() throws {
      let container = try seeded()
      let context = ModelContext(container)
      let recipe = try #require(try context.fetch(FetchDescriptor<RecipeRecord>()).first)
      let today = try DebugSeed.today()
      let target = MealTarget(day: today, slot: .lunch)
      for scheme in [ColorScheme.light, .dark] {
        let sheet = DroppedRecipeSheet(
          recipe: recipe, target: target, position: 0, days: today.weekDays(), today: today
        ) { _ in }
        #expect(
          renders(
            sheet.modelContainer(container).environment(\.colorScheme, scheme), width: 420,
            height: 700), "\(scheme)")
      }
    }

    @Test func theEntrySheetRendersForARecipeAndForFreeText() throws {
      let container = try seeded()
      let entries = try ModelContext(container).fetch(FetchDescriptor<PlanEntryRecord>())
      let start = try DebugSeed.today().startOfWeek()
      let meals = WeekSnapshot(start: start, records: entries).meals
      #expect(meals.count == 5)
      let text = PlanEntry(
        id: UUID(), date: start, slot: .lunch, title: "Leftovers", recipe: nil, servings: nil,
        position: 0, brewed: false)
      for meal in meals + [text] {
        for scheme in [ColorScheme.light, .dark] {
          let view = EntrySheet(
            meal: meal, days: start.weekDays(), slotSize: 2, onSave: { _ in }, onShift: { _ in },
            onRemove: {}
          )
          .environment(\.colorScheme, scheme)
          #expect(renders(view, width: 420, height: 560))
        }
      }
    }

    @Test func plannedBatchSummariesAndEditorRenderAtBothWeekWidthsAndAppearances() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let start = LocalDate("2026-10-05")!
      let recipe = RecipeRecord(title: "Soup")
      context.insert(recipe)
      let batch = try WeekPlan.createBatch(
        recipe: recipe, weekStart: start, totalServings: 4, in: context)
      try context.save()
      let planner = WeekPlanner(
        start: start, today: start, startsOn: .monday, isCurrent: true, onPrevious: {},
        onNext: {}, onThisWeek: {}, onStartsOn: { _ in })
      for scheme in [ColorScheme.light, .dark] {
        for (width, height) in [(1100.0, 800.0), (390.0, 800.0)] {
          #expect(
            renders(
              planner.modelContainer(container).environment(\.colorScheme, scheme),
              width: width, height: height), "week batch summary \(scheme) \(width)")
        }
        #expect(
          renders(
            BatchSummary(batch: batch, onOpen: {}).environment(\.colorScheme, scheme),
            width: 390, height: 140))
        #expect(
          renders(
            PlannedBatchSheet(batch: batch, onRemoved: {}).modelContainer(container)
              .environment(\.colorScheme, scheme), width: 440, height: 680),
          "batch editor \(scheme)")
        #expect(
          renders(
            BatchManagementButton(batches: [batch], action: {}).environment(\.colorScheme, scheme),
            width: 240, height: 70), "batch entry \(scheme)")
        #expect(
          renders(
            BatchManagementSheet(batches: [batch], weekStart: start, today: start)
              .modelContainer(container).environment(\.colorScheme, scheme),
            width: 390, height: 800), "batch list \(scheme)")
      }
    }

    @Test func batchSheetSupportsEmptyAndTwentyOneSeparateRecipeBatches() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let start = LocalDate("2026-10-19")!
      let recipe = RecipeRecord(title: "A recipe added more than once")
      context.insert(recipe)
      var batches: [PlannedBatchRecord] = []
      for _ in 0..<21 {
        batches.append(
          try WeekPlan.createBatch(
            recipe: recipe, weekStart: start, totalServings: 4, in: context))
      }
      try context.save()
      for scheme in [ColorScheme.light, .dark] {
        let empty = BatchManagementSheet(batches: [], weekStart: start, today: start)
        #expect(
          renders(
            empty.modelContainer(container).environment(\.colorScheme, scheme),
            width: 390, height: 760), "empty list \(scheme)")
        let populated = BatchManagementSheet(
          batches: batches, weekStart: start, today: start)
        #expect(
          renders(
            populated.modelContainer(container).environment(\.colorScheme, scheme),
            width: 320, height: 760), "21 distinct batches \(scheme)")
        #expect(
          renders(
            BatchManagementButton(batches: batches, action: {}).environment(\.colorScheme, scheme),
            width: 240, height: 70), "21-batch entry \(scheme)")
      }
    }

    @Test func invalidBatchAssignmentHasRepairControlsAndRenameableBatchEntryHasServings() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let start = LocalDate("2026-10-05")!
      let batch = PlannedBatchRecord(
        weekStart: start, title: "Soup", totalServings: 4, ingredientYield: 4)
      let entry = PlanEntryRecord(day: start, slot: .dinner, title: "Soup", servings: nil)
      entry.batch = batch
      entry.dayKey = "unreadable"
      context.insert(batch)
      context.insert(entry)
      let repair = BatchAssignmentEditor(entry: entry, batch: batch)
      let limits = PlannedEntryLimits(batch: batch, entry: entry, records: [entry])
      let row = EntrySheet(
        meal: PlanEntry(
          id: entry.id, date: start, slot: .dinner, title: "Soup", recipe: nil, servings: nil,
          position: 0, brewed: false),
        days: start.weekDays(), slotSize: 1, onSave: { _ in }, onShift: { _ in },
        onRemove: {}, limits: limits)
      for scheme in [ColorScheme.light, .dark] {
        #expect(
          renders(
            repair.modelContainer(container).environment(\.colorScheme, scheme),
            width: 420, height: 520))
        #expect(
          renders(row.environment(\.colorScheme, scheme), width: 420, height: 520))
      }
    }

    @Test func theNoticeBannerRendersWithAndWithoutUndo() {
      for undo in [true, false] {
        for scheme in [ColorScheme.light, .dark] {
          let view = WeekNoticeBanner(text: Copy.week.removed("Soup").text, canUndo: undo) {}
            .environment(\.colorScheme, scheme)
          #expect(renders(view, width: 390, height: 120))
        }
      }
    }

    @Test func theRecipePageActionRendersEnabledAndForABanishedRecipe() throws {
      let container = try seeded()
      let recipe = try #require(
        ModelContext(container).fetch(FetchDescriptor<RecipeRecord>()).first)
      let action = RecipeAddToWeekAction(recipe: recipe, scale: .servings(4))
      let live = action.modelContainer(container)
      #expect(renders(live, width: 300, height: 80))
      RecipeLibrary.banish(recipe)
      #expect(renders(live, width: 300, height: 80))
    }
  }
#endif
