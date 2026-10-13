import CauldronKit
import SwiftData
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Cauldron

/// A recipe in its own window, a recipe dragged onto the week, and the Mac layouts at a wide
/// window.
@MainActor
@Suite("Mac windows and dragging")
struct MacWindowsTests {
  private let monday = LocalDate("2026-10-05")!

  private func context() throws -> ModelContext {
    ModelContext(try CauldronStore.container(.inMemory))
  }

  private func recipe(
    _ title: String, servings: Int? = 4, in context: ModelContext
  ) -> RecipeRecord {
    let record = RecipeRecord(title: title)
    record.servings = servings
    context.insert(record)
    return record
  }

  private func entries(in context: ModelContext) throws -> [PlanEntryRecord] {
    try context.fetch(FetchDescriptor<PlanEntryRecord>())
  }

  // MARK: The recipe window

  @Test func theWindowOpensItsRecipeAndFollowsItBeingBanishedAndRestored() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let other = recipe("Stew", in: context)
    let all = [soup, other]
    guard case .open(let found) = RecipeWindowState.resolve(soup.id, in: all) else {
      Issue.record("expected the recipe")
      return
    }
    #expect(found === soup)

    RecipeLibrary.banish(soup)
    guard case .banished(let gone) = RecipeWindowState.resolve(soup.id, in: all) else {
      Issue.record("expected a banished recipe")
      return
    }
    #expect(gone === soup)
    if case .open = RecipeWindowState.resolve(other.id, in: all) {
    } else {
      Issue.record("banishing one recipe left the other alone")
    }

    RecipeLibrary.restore(soup)
    if case .open = RecipeWindowState.resolve(soup.id, in: all) {
    } else {
      Issue.record("expected the recipe back")
    }
  }

  @Test func aRecipeThatIsntThereReadsAsMissing() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    if case .missing = RecipeWindowState.resolve(UUID(), in: [soup]) {
    } else {
      Issue.record("an unknown id is missing")
    }
    if case .missing = RecipeWindowState.resolve(soup.id, in: []) {
    } else {
      Issue.record("a purged recipe is missing")
    }
  }

  @Test func theRequestSurvivesBeingSavedWithTheWindow() throws {
    let request = RecipeWindowRequest(recipeID: UUID())
    let data = try JSONEncoder().encode(request)
    #expect(try JSONDecoder().decode(RecipeWindowRequest.self, from: data) == request)
  }

  #if DEBUG
    private func seeded() throws -> (container: ModelContainer, recipes: [RecipeRecord]) {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      try DebugSeed.populate(context, today: DebugSeed.today())
      return (container, try context.fetch(FetchDescriptor<RecipeRecord>()))
    }

    private func draws(_ view: some View, width: CGFloat, height: CGFloat) -> Bool {
      ImageRenderer(content: view.frame(width: width, height: height)).cgImage != nil
    }

    @Test func theWindowDrawsARecipeABanishedOneAndAMissingOne() throws {
      let (container, recipes) = try seeded()
      let soup = try #require(recipes.first)
      for scheme in [ColorScheme.light, .dark] {
        let live = RecipeWindow(request: RecipeWindowRequest(recipeID: soup.id))
          .modelContainer(container).environment(\.colorScheme, scheme)
        #expect(draws(live, width: 920, height: 800), "open in \(scheme)")
        let missing = RecipeWindow(request: RecipeWindowRequest(recipeID: UUID()))
          .modelContainer(container).environment(\.colorScheme, scheme)
        #expect(draws(missing, width: 920, height: 800), "missing in \(scheme)")
      }
      RecipeLibrary.banish(soup)
      let banished = RecipeWindow(request: RecipeWindowRequest(recipeID: soup.id))
        .modelContainer(container)
      #expect(draws(banished, width: 920, height: 800))
    }

    @Test func theRecipePageDrawsInItsOwnWindow() throws {
      let (container, recipes) = try seeded()
      for recipe in recipes {
        let view = RecipeDetailView(recipe: recipe, inOwnWindow: true) {}
          .modelContainer(container)
        #expect(draws(view, width: 920, height: 800), "\(recipe.title)")
      }
    }

    @Test func theScreensDrawAtAWideMacWindow() throws {
      let (container, _) = try seeded()
      let today = try DebugSeed.today()
      let context = ModelContext(container)
      let targets = try #require(try context.current(TargetsRecord.self))
      let sync = SyncStatusModel(account: FakeICloudAccount(.synced))
      for scheme in [ColorScheme.light, .dark] {
        let diary = DiaryView(today: today, targets: targets, openTargets: {})
          .modelContainer(container)
        let weight = NavigationStack { WeightView(today: today) }.modelContainer(container)
        let settings = SettingsView()
          .environment(sync).environment(RecipeAIService.offline())
        let gather = GatherRoot().modelContainer(container)
        let week = WeekRoot().modelContainer(container)
        let recipes = RecipesRoot().modelContainer(container)
        let all: [AnyView] = [
          AnyView(diary), AnyView(weight), AnyView(settings), AnyView(gather), AnyView(week),
          AnyView(recipes),
        ]
        for (index, view) in all.enumerated() {
          #expect(
            draws(view.environment(\.colorScheme, scheme), width: 1400, height: 900),
            "screen \(index) in \(scheme)")
        }
      }
    }

    @Test func theTargetsFormDrawsAtAWideMacWindow() throws {
      let container = try CauldronStore.container(.inMemory)
      let context = ModelContext(container)
      let view = TargetsView(context: context).modelContainer(container)
      #expect(draws(view, width: 1400, height: 900))
    }
  #endif

  // MARK: Dragging a recipe

  @Test func aRecipeDragCarriesTheRecipeIdAndReadsBack() throws {
    let id = UUID()
    let drag = RecipeDrag(id: id)
    #expect(try RecipeDrag(payload: drag.payload) == drag)
    #expect(String(data: drag.payload, encoding: .utf8) == "cauldron-recipe:\(id.uuidString)")
  }

  @Test func aRecipeDragTravelsAsTransferablePlainText() async throws {
    let drag = RecipeDrag(id: UUID())
    let data = try await drag.exported(as: .utf8PlainText)
    #expect(try await RecipeDrag(importing: data, contentType: .utf8PlainText) == drag)
  }

  @Test func onlyOurOwnPayloadReadsAsARecipe() throws {
    let meal = try JSONEncoder().encode(MealDrag(id: UUID()))
    let notes = [
      meal, Data("hello".utf8), Data("cauldron-recipe:".utf8),
      Data("cauldron-recipe:not-a-uuid".utf8), Data(), Data([0xFF, 0xFE]),
    ]
    for payload in notes {
      #expect(throws: RecipeDrag.NotARecipe.self) { try RecipeDrag(payload: payload) }
    }
    // And a recipe isn't mistaken for a meal by the destination that takes meals.
    let recipePayload = RecipeDrag(id: UUID()).payload
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(MealDrag.self, from: recipePayload)
    }
  }

  // MARK: Dropping a recipe on the week

  @Test func aDroppedRecipeIsPlannedOnThatDayWithItsOwnServings() throws {
    let context = try context()
    let soup = recipe("Soup", servings: 6, in: context)
    let tuesday = monday.adding(days: 1)
    let entry = try WeekPlan.stir(
      recipeID: soup.id, at: MealTarget(day: tuesday, slot: WeekPlan.defaultSlot), into: context)
    #expect(entry.recipe === soup)
    #expect(entry.title == "Soup")
    #expect(entry.dayKey == "2026-10-06")
    #expect(entry.slot == .dinner)
    #expect(entry.servings == nil, "it keeps following the recipe's own servings")
    #expect(try entries(in: context).count == 1)
  }

  @Test func aDropOnAMealGoesInThatMealAfterWhatIsThere() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    try WeekPlan.stirText("Leftovers", at: MealTarget(day: monday, slot: .lunch), into: context)
    let entry = try WeekPlan.stir(
      recipeID: soup.id, at: MealTarget(day: monday, slot: .lunch), into: context)
    #expect(entry.slot == .lunch)
    #expect(entry.position == 1)
  }

  @Test func aBanishedRecipeCantBeDroppedOnTheWeek() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    RecipeLibrary.banish(soup)
    #expect(throws: WeekPlanError.recipeBanished) {
      try WeekPlan.stir(
        recipeID: soup.id, at: MealTarget(day: monday, slot: .dinner), into: context)
    }
    #expect(try entries(in: context).isEmpty)
  }

  @Test func aRecipeThatIsntThereCantBeDropped() throws {
    let context = try context()
    #expect(throws: WeekPlanError.recipeMissing) {
      try WeekPlan.stir(
        recipeID: UUID(), at: MealTarget(day: monday, slot: .dinner), into: context)
    }
    #expect(try entries(in: context).isEmpty)
    #expect(WeekPlanError.recipeMissing.message == Copy.week.couldntSave)
  }

  @Test func aFullMealRefusesADroppedRecipe() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let target = MealTarget(day: monday, slot: .dinner)
    for _ in 0..<WeekLimits.perSlot {
      try WeekPlan.stir(soup, at: target, servings: nil, into: context)
    }
    #expect(throws: WeekPlanError.slotFull) {
      try WeekPlan.stir(recipeID: soup.id, at: target, into: context)
    }
    #expect(try entries(in: context).count == WeekLimits.perSlot)
  }

  @Test func aRefusedDropRollsBackWhenCommitted() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    RecipeLibrary.banish(soup)
    #expect(throws: WeekPlanError.recipeBanished) {
      try WeekPlan.commit(in: context) {
        try WeekPlan.stir(
          recipeID: soup.id, at: MealTarget(day: monday, slot: .dinner), into: context)
      }
    }
    #expect(try entries(in: context).isEmpty)
  }
}
