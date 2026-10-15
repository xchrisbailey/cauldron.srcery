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

  @Test func aDroppedRecipeOpensTheSpreadSetToTheDroppedDayAndMeal() throws {
    let context = try context()
    let soup = recipe("Soup", servings: 6, in: context)
    let found = try WeekPlan.droppedRecipe(id: soup.id, in: context)
    #expect(found === soup)
    // Nothing is planned until the cook stirs it in from the days step.
    #expect(try entries(in: context).isEmpty)

    let tuesday = monday.adding(days: 1)
    let plan = SpreadPlan(
      days: monday.weekDays(), anchor: tuesday, slot: .lunch, recipeServings: soup.servings)
    #expect(plan.anchor == tuesday && plan.slot == .lunch)
    #expect(plan.entries == [DayServings(date: tuesday, servings: 1)])
    try WeekPlan.stir(soup, spread: plan, into: context)
    let entry = try #require(try entries(in: context).first)
    #expect(entry.dayKey == "2026-10-06" && entry.slot == .lunch && entry.recipe === soup)
  }

  @Test func aDropOnAMealCardPlacesTheRecipeBeforeIt() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let lunch = MealTarget(day: monday, slot: .lunch)
    try WeekPlan.stirText("Leftovers", at: lunch, into: context)
    try WeekPlan.stirText("Salad", at: lunch, into: context)
    let all = try entries(in: context)
    let salad = try #require(all.first { $0.title == "Salad" })
    // Dropped on the second card: it goes in front of it, as `dropAt` does on the web.
    let position = try #require(WeekPlan.dropAt(all, target: lunch, before: salad.id))
    #expect(position == 1)
    let plan = SpreadPlan(
      days: monday.weekDays(), anchor: monday, slot: .lunch, recipeServings: soup.servings)
    try WeekPlan.stir(
      soup, spread: plan,
      placed: Placement(day: monday, slot: .lunch, position: position), into: context)
    #expect(try titles(lunch, in: context) == ["Leftovers", "Soup", "Salad"])
    #expect(try positions(lunch, in: context) == [0, 1, 2])
  }

  @Test func aDropOnTheMealItselfGoesAtTheEnd() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let lunch = MealTarget(day: monday, slot: .lunch)
    try WeekPlan.stirText("Leftovers", at: lunch, into: context)
    let all = try entries(in: context)
    #expect(WeekPlan.dropAt(all, target: lunch, before: nil) == nil)
    // A card that is not in the meal (gone since the drag began) also means the end.
    #expect(WeekPlan.dropAt(all, target: lunch, before: UUID()) == nil)
    let plan = SpreadPlan(
      days: monday.weekDays(), anchor: monday, slot: .lunch, recipeServings: soup.servings)
    try WeekPlan.stir(soup, spread: plan, into: context)
    #expect(try titles(lunch, in: context) == ["Leftovers", "Soup"])
  }

  @Test func theDropPositionHoldsOnlyForTheDroppedDayAndMeal() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let tuesday = monday.adding(days: 1)
    for day in [monday, tuesday] {
      try WeekPlan.stirText("Early", at: dinner(day), into: context)
    }
    let placed = Placement(day: monday, slot: .dinner, position: 0)
    try WeekPlan.stir(
      soup,
      days: [DayServings(date: monday, servings: 1), DayServings(date: tuesday, servings: 1)],
      slot: .dinner, placed: placed, into: context)
    #expect(try titles(dinner(monday), in: context) == ["Soup", "Early"])
    #expect(try titles(dinner(tuesday), in: context) == ["Early", "Soup"])

    // The cook moved the stir to another meal in the spread: the position no longer applies.
    try WeekPlan.stirText("First", at: MealTarget(day: monday, slot: .snack), into: context)
    try WeekPlan.stir(
      soup, days: [DayServings(date: monday, servings: 1)], slot: .snack, placed: placed,
      into: context)
    #expect(try titles(MealTarget(day: monday, slot: .snack), in: context) == ["First", "Soup"])
  }

  @Test func aBanishedRecipeCantBeDroppedOnTheWeek() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    RecipeLibrary.banish(soup)
    #expect(throws: WeekPlanError.recipeBanished) {
      try WeekPlan.droppedRecipe(id: soup.id, in: context)
    }
    #expect(try entries(in: context).isEmpty)
  }

  @Test func aRecipeThatIsntThereCantBeDropped() throws {
    let context = try context()
    #expect(throws: WeekPlanError.recipeMissing) {
      try WeekPlan.droppedRecipe(id: UUID(), in: context)
    }
    #expect(try entries(in: context).isEmpty)
    #expect(WeekPlanError.recipeMissing.message == Copy.week.couldntSave)
  }

  @Test func aFullMealRefusesADroppedRecipeAtTheSpreadStep() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let target = MealTarget(day: monday, slot: .dinner)
    for _ in 0..<WeekLimits.perSlot {
      try WeekPlan.stir(soup, at: target, servings: nil, into: context)
    }
    try context.save()
    let plan = SpreadPlan(
      days: monday.weekDays(), anchor: monday, slot: .dinner, recipeServings: soup.servings)
    #expect(throws: WeekPlanError.slotFull) {
      try WeekPlan.stir(soup, spread: plan, into: context)
    }
    #expect(try entries(in: context).count == WeekLimits.perSlot)
  }

  @Test func aRefusedSpreadRollsBackWhenCommitted() throws {
    let context = try context()
    let soup = recipe("Soup", in: context)
    let plan = SpreadPlan(
      days: monday.weekDays(), anchor: monday, slot: .dinner, recipeServings: soup.servings)
    RecipeLibrary.banish(soup)
    try context.save()
    #expect(throws: WeekPlanError.recipeBanished) {
      try WeekPlan.stir(soup, spread: plan, into: context)
    }
    #expect(try entries(in: context).isEmpty)
  }

  private func dinner(_ day: LocalDate) -> MealTarget { MealTarget(day: day, slot: .dinner) }

  private func titles(_ target: MealTarget, in context: ModelContext) throws -> [String] {
    WeekPlan.inSlot(try entries(in: context), target).map(\.title)
  }

  private func positions(_ target: MealTarget, in context: ModelContext) throws -> [Int] {
    WeekPlan.inSlot(try entries(in: context), target).map(\.position)
  }
}
