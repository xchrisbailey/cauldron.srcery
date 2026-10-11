import CauldronKit
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
        let recipePage = StirRecipeSheet(recipe: recipe, scale: .servings(6), today: today) { _ in }
        #expect(
          renders(
            recipePage.modelContainer(container).environment(\.colorScheme, scheme), width: 420,
            height: 360))
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
