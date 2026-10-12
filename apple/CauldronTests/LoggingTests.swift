import CauldronKit
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Cauldron

@MainActor
@Suite("Recents and favourites")
struct QuickFoodTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!
  private let container: ModelContainer
  private let context: ModelContext

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
  }

  @discardableResult
  private func log(
    _ name: String, amount: String? = nil, servings: Double = 1, kcal: Double = 100,
    daysAgo: Int = 0, source: DiarySource = .manual, recipe: RecipeRecord? = nil,
    pending: Bool = false, createdAt: Date? = nil
  ) -> DiaryEntryRecord {
    let entry = DiaryEntryRecord(
      day: today.adding(days: -daysAgo), slot: .lunch, name: name, servings: servings,
      source: source)
    entry.amount = amount
    entry.macros = Macros(calories: kcal, protein: 5, carbs: 10, fat: 2)
    entry.recipe = recipe
    entry.macrosPending = pending
    if let createdAt { entry.createdAt = createdAt }
    context.insert(entry)
    return entry
  }

  private func foods() throws -> QuickFoods {
    try context.save()
    return QuickFoodList.foods(
      favourites: try context.fetch(FetchDescriptor<FavouriteRecord>()),
      entries: try context.fetch(FetchDescriptor<DiaryEntryRecord>()), today: today)
  }

  // MARK: Recents

  @Test func recentsAreGroupedByNameAndAmountMostOftenFirst() throws {
    log("Apple", amount: "1 medium", daysAgo: 3)
    log("apple ", amount: " 1 MEDIUM", daysAgo: 1)
    log("Toast", daysAgo: 0)
    log("Apple", amount: "2 small", daysAgo: 2)
    log("Apple", amount: "1 medium", daysAgo: 5)
    let recents = try foods().recents
    #expect(recents.map(\.food.name) == ["apple ", "Toast", "Apple"])
    #expect(recents.map(\.count) == [3, 1, 1])
  }

  @Test func equalCountsPutTheMostRecentFirst() throws {
    log("Old", daysAgo: 9)
    log("New", daysAgo: 1)
    log("Middle", daysAgo: 4)
    #expect(try foods().recents.map(\.food.name) == ["New", "Middle", "Old"])
  }

  @Test func aRecentIsAsItWasLastLogged() throws {
    log("Soup", amount: "1 bowl", servings: 1, kcal: 200, daysAgo: 5)
    let last = log("Soup", amount: "1 bowl", servings: 2, kcal: 250, daysAgo: 1)
    let recent = try #require(try foods().recents.first)
    #expect(recent.count == 2 && recent.lastLoggedOn == today.adding(days: -1))
    #expect(recent.lastEntryId == last.id)
    #expect(recent.food.servings == 2 && recent.food.macros.calories == 250)
  }

  @Test func theLatestOfTwoOnTheSameDayIsTheOneAddedLast() throws {
    log("Soup", servings: 1, createdAt: Date(timeIntervalSince1970: 1000))
    log("Soup", servings: 3, createdAt: Date(timeIntervalSince1970: 2000))
    #expect(try foods().recents.first?.food.servings == 3)
  }

  @Test func onlyTheLastSixtyDaysAndThirtyFoodsAreOffered() throws {
    log("Fresh", daysAgo: 60)
    log("Stale", daysAgo: 61)
    #expect(try foods().recents.map(\.food.name) == ["Fresh"])
    for index in 0..<40 { log("Food \(index)", daysAgo: index % 50) }
    #expect(try foods().recents.count == QuickFoodList.recentMax)
  }

  @Test func aRecipeIsTheSameFoodWhateverItsNameNow() throws {
    let recipe = RecipeRecord(title: "Soup")
    context.insert(recipe)
    log("Soup", daysAgo: 4, source: .recipe, recipe: recipe)
    log("Tomato soup", daysAgo: 1, source: .recipe, recipe: recipe)
    let recents = try foods().recents
    #expect(recents.count == 1 && recents[0].count == 2)
    #expect(recents[0].food.name == "Tomato soup" && recents[0].food.recipeId == recipe.id)
  }

  @Test func aMealWaitingForItsNumbersIsNotOffered() throws {
    log("Described", pending: true)
    log("Typed")
    #expect(try foods().recents.map(\.food.name) == ["Typed"])
  }

  // MARK: Favourites

  @Test func starringAnEntryMakesItAFavouriteAndTakesItOutOfRecents() throws {
    let soup = log("Soup", amount: "1 bowl", servings: 2, kcal: 200)
    log("Toast")
    try context.save()
    try FavouriteWrites.star(soup, in: context)
    let result = try foods()
    #expect(result.favourites.map(\.food.name) == ["Soup"])
    #expect(
      result.favourites[0].food.servings == 2 && result.favourites[0].food.macros.calories == 200)
    #expect(result.recents.map(\.food.name) == ["Toast"])
  }

  @Test func oneFavouritePerFoodAndStarringAgainUpdatesIt() throws {
    let first = log("Soup", servings: 1, kcal: 200, daysAgo: 3)
    try FavouriteWrites.star(first, in: context)
    let again = log("Soup", servings: 2, kcal: 260, daysAgo: 0)
    try FavouriteWrites.star(again, in: context)
    let rows = try context.fetch(FetchDescriptor<FavouriteRecord>())
    #expect(rows.count == 1)
    #expect(rows[0].servings == 2 && rows[0].calories == 260)
    #expect(rows[0].key == quickFoodKey(again.quickFood))
  }

  @Test func unstarringTakesEveryRowForTheFoodOff() throws {
    let soup = log("Soup")
    try FavouriteWrites.star(soup, in: context)
    // A second device made its own row for the same food.
    let twin = FavouriteRecord(key: FavouriteWrites.key(of: soup), name: "Soup", source: .manual)
    context.insert(twin)
    try context.save()
    try FavouriteWrites.unstar(key: FavouriteWrites.key(of: soup), in: context)
    #expect(try context.fetchCount(FetchDescriptor<FavouriteRecord>()) == 0)
    #expect(try foods().recents.map(\.food.name) == ["Soup"])
  }

  @Test func favouritesAreByNameAndOnePerFoodByTheKeeperRule() throws {
    let a = FavouriteRecord(key: "food:b|", name: "Bread", source: .manual)
    let b = FavouriteRecord(key: "food:a|", name: "apple", source: .manual)
    let older = FavouriteRecord(key: "food:c|", name: "Cake", source: .manual)
    older.updatedAt = Date(timeIntervalSince1970: 1)
    let newer = FavouriteRecord(key: "food:c|", name: "Cake (new)", source: .manual)
    newer.updatedAt = Date(timeIntervalSince1970: 2)
    for row in [a, b, older, newer] { context.insert(row) }
    #expect(
      QuickFoodList.favouriteList([a, b, older, newer]).map(\.food.name)
        == ["apple", "Bread", "Cake (new)"])
  }

  @Test func aMealWaitingForItsNumbersCantBeStarred() throws {
    let pending = log("Described", pending: true)
    #expect(throws: FavouriteWrites.Failure.pending) {
      try FavouriteWrites.star(pending, in: context)
    }
    #expect(try context.fetchCount(FetchDescriptor<FavouriteRecord>()) == 0)
  }

  // MARK: Logging one again

  @Test func loggingAFoodAgainCopiesItAsItWas() throws {
    let recipe = RecipeRecord(title: "Soup")
    context.insert(recipe)
    let soup = log(
      "Soup", amount: "1 bowl", servings: 1.5, kcal: 210, source: .recipe, recipe: recipe)
    let new = QuickFoodList.entry(for: soup.quickFood, in: context)
    #expect(new.name == "Soup" && new.amount == "1 bowl" && new.servings == 1.5)
    #expect(new.macros == soup.macros && new.source == .recipe)
    #expect(new.recipe === recipe)
    let added = try DiaryEditor(context: context).add([new], on: today, slot: .dinner)
    #expect(added[0].recipe === recipe && added[0].slot == .dinner && added[0].servings == 1.5)
  }

  @Test func theRecipeLinkIsLetGoWhenTheRecipeIsGone() throws {
    let food = QuickFood(
      name: "Soup", amount: nil, servings: 1, macros: Macros(calories: 100), source: .recipe,
      recipeId: UUID())
    let new = QuickFoodList.entry(for: food, in: context)
    #expect(new.recipe == nil && new.source == .recipe)
  }

  @Test func theQuickFoodsAreLoggedThroughTheSheetsContextSoHealthFollows() async throws {
    let fake = FakeHealthStore()
    let suite = "logging-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    let sync = HealthSync(
      store: fake, setup: HealthSetup(isConfigured: true), defaults: defaults,
      now: { [today] in
        Calendar.current.date(
          from: DateComponents(year: today.year, month: today.month, day: today.day, hour: 12))
          ?? .now
      })
    await sync.connect()
    let soup = log("Soup", kcal: 200)
    try context.save()
    // What the Recent tab does: build the entry from the food, log it through the editor.
    let again = try DiaryEditor(context: context, health: sync).add(
      [QuickFoodList.entry(for: soup.quickFood, in: context)], on: today, slot: .dinner)[0]
    await sync.settle()
    let held = await fake.held
    #expect(held[HealthNutrition.syncID(entry: again.id, nutrient: .energy)]?.value == 200)
    #expect(held.keys.filter { $0.contains(again.id.uuidString.lowercased()) }.count == 4)
  }
}

@MainActor
@Suite("Logging a recipe")
struct RecipeLoggingTests {
  private let today = LocalDate(year: 2026, month: 10, day: 10)!
  private let container: ModelContainer
  private let context: ModelContext

  init() throws {
    container = try CauldronStore.container(.inMemory)
    context = ModelContext(container)
  }

  private func recipe(
    _ title: String = "Soup", kcal: Double? = 260, protein: Double? = 12, carbs: Double? = 38,
    fat: Double? = 6, tags: String = ""
  ) -> RecipeRecord {
    let recipe = RecipeRecord(title: title)
    recipe.macros = Macros(calories: kcal, protein: protein, carbs: carbs, fat: fat)
    recipe.searchText = (title + " " + tags).lowercased()
    context.insert(recipe)
    return recipe
  }

  @Test func aRecipeLogsPerServingNumbersTimesServingsWithALink() throws {
    let soup = recipe()
    var draft = RecipeLogDraft(slot: .lunch, day: today)
    #expect(draft.servings == "1")
    draft.servings = "1,5"
    #expect(draft.totals(of: soup) == MacroTotals(calories: 390, protein: 18, carbs: 57, fat: 9))
    let new = try #require(draft.entry(for: soup))
    #expect(new.name == "Soup" && new.servings == 1.5 && new.source == .recipe)
    #expect(new.macros == Macros(calories: 260, protein: 12, carbs: 38, fat: 6))
    #expect(new.recipe === soup)

    let added = try DiaryEditor(context: context).add([new], on: today, slot: .lunch)
    #expect(added[0].recipe?.id == soup.id && added[0].servings == 1.5)
  }

  @Test func theEntryKeepsTheNumbersItWasLoggedWith() throws {
    let soup = recipe()
    let entry = try #require(RecipeLogDraft(slot: .lunch, day: today).entry(for: soup))
    let added = try DiaryEditor(context: context).add([entry], on: today, slot: .lunch)[0]
    soup.macros = Macros(calories: 999, protein: 99, carbs: 99, fat: 99)
    soup.title = "Renamed"
    #expect(added.macros == Macros(calories: 260, protein: 12, carbs: 38, fat: 6))
    #expect(added.name == "Soup")
  }

  @Test func oneServingIsTheDefaultSoLoggingNeedsNoTyping() throws {
    let draft = RecipeLogDraft(slot: .dinner, day: today)
    #expect(draft.servingsValue == 1 && draft.servingsError == nil)
    #expect(draft.entry(for: recipe())?.servings == 1)
  }

  @Test func theServingsFollowTheCooksChoiceOfStartingAmount() {
    #expect(RecipeLogDraft(slot: .lunch, day: today, servings: 0.5).servings == "0.5")
    #expect(RecipeLogDraft(slot: .lunch, day: today, servings: 2).servings == "2")
  }

  @Test func badServingsAreRefused() throws {
    let soup = recipe()
    for text in ["0", "-1", "101", "abc", "", "nan", "inf"] {
      var draft = RecipeLogDraft(slot: .lunch, day: today)
      draft.servings = text
      #expect(draft.entry(for: soup) == nil, "\(text)")
      #expect(draft.servingsError?.text == "Use a number from 0 to 100.")
    }
    var draft = RecipeLogDraft(slot: .lunch, day: today)
    draft.servings = "100"
    #expect(draft.entry(for: soup) != nil)
  }

  @Test func theServingButtonsStepByAQuarter() {
    var draft = RecipeLogDraft(slot: .lunch, day: today)
    draft.nudge(by: RecipeLogDraft.step)
    #expect(draft.servings == "1.25")
    draft.nudge(by: -RecipeLogDraft.step * 10)
    #expect(draft.servings == "0.25")
    #expect(RecipeLogDraft.quickServings == [0.5, 1, 1.5, 2])
  }

  @Test func aRecipeWithGapsLogsWhatItKnowsAndShowsTheGap() throws {
    let bare = recipe("Bare", kcal: 300, protein: nil, carbs: nil, fat: nil)
    #expect(hasGaps(bare.macros))
    let draft = RecipeLogDraft(slot: .lunch, day: today)
    #expect(draft.totals(of: bare) == MacroTotals(calories: 300, protein: 0, carbs: 0, fat: 0))
    let none = recipe("None", kcal: nil, protein: nil, carbs: nil, fat: nil)
    let entry = try #require(draft.entry(for: none))
    #expect(entry.macros == Macros())
    // It logs, with the numbers unknown.
    let added = try DiaryEditor(context: context).add([entry], on: today, slot: .lunch)
    #expect(added[0].calories == nil)
  }

  @Test func theMealFollowsTheHour() {
    #expect(suggestedSlot(hour: 7) == .breakfast && suggestedSlot(hour: 10) == .breakfast)
    #expect(suggestedSlot(hour: 11) == .lunch && suggestedSlot(hour: 14) == .lunch)
    #expect(suggestedSlot(hour: 15) == .dinner && suggestedSlot(hour: 20) == .dinner)
    #expect(suggestedSlot(hour: 21) == .snack && suggestedSlot(hour: 3) == .breakfast)
  }

  // MARK: The picker

  @Test func theListSearchesYourRecipesAndSkipsBanishedOnes() {
    let soup = recipe("Tomato soup", tags: "tomato basil")
    let cake = recipe("Cake")
    let gone = recipe("Banished soup")
    gone.deletedAt = .now
    #expect(
      Set(RecipePicker.matches([soup, cake, gone], query: "").map(\.title))
        == ["Tomato soup", "Cake"])
    #expect(
      RecipePicker.matches([soup, cake, gone], query: "soup").map(\.title) == ["Tomato soup"])
    #expect(
      RecipePicker.matches([soup, cake, gone], query: "basil").map(\.title) == ["Tomato soup"])
    #expect(RecipePicker.matches([soup, cake, gone], query: "nothing").isEmpty)
  }

  @Test func theListIsByTitleAndShowsThePerServingNumbers() {
    let b = recipe("Beans", kcal: 320)
    b.totalMinutes = 25
    let a = recipe("Apple pie", kcal: nil, protein: nil, carbs: nil, fat: nil)
    #expect(RecipePicker.matches([b, a], query: "").map(\.title) == ["Apple pie", "Beans"])
    #expect(RecipePicker.detail(b) == "320 kcal a serving · 25 min")
    #expect(RecipePicker.detail(a) == "No calories yet")
  }

  // MARK: Where it logs

  @Test func aFullDayRefusesAndTheFormSaysSo() throws {
    let soup = recipe()
    try DiaryWrites.add(
      (0..<TrackerLimits.perDay).map {
        NewEntry(name: "F\($0)", macros: Macros(), source: .manual)
      },
      on: today, slot: .snack, in: context)
    let entry = try #require(RecipeLogDraft(slot: .lunch, day: today).entry(for: soup))
    #expect(throws: DiaryWrites.Failure.dayFull) {
      try DiaryEditor(context: self.context).add([entry], on: self.today, slot: .lunch)
    }
  }

  @Test func theRecipeLogsOnTheDayAndMealChosen() throws {
    let soup = recipe()
    var draft = RecipeLogDraft(slot: .lunch, day: today)
    draft.slot = .dinner
    draft.day = today.adding(days: -2)
    let entry = try #require(draft.entry(for: soup))
    let added = try DiaryEditor(context: context).add([entry], on: draft.day, slot: draft.slot)
    #expect(added[0].day == today.adding(days: -2) && added[0].slot == .dinner)
  }

  // MARK: Screens

  private func draws(_ view: some View) -> Bool {
    ImageRenderer(content: view.frame(width: 390, height: 800)).cgImage != nil
  }

  @Test func theAddSheetNowOffersRecentRecipeAndQuickAdd() {
    #expect(AddWay.available == [.recents, .describe, .recipe, .quick].filter(\.isAvailable))
    #expect(AddWay.available.contains(.recents) && AddWay.available.contains(.recipe))
    #expect(AddWay.available.first == .recents)
  }

  @Test func theTabsAndSheetsDraw() throws {
    let soup = recipe()
    let bare = recipe("Bare", kcal: nil, protein: nil, carbs: nil, fat: nil)
    let log = AddContext(day: today, slot: .lunch) { _ in nil }
    let entry = DiaryEntryRecord(day: today, slot: .lunch, name: "Toast", source: .manual)
    entry.macros = Macros(calories: 100)
    context.insert(entry)
    let star = FavouriteRecord(key: "food:apple|", name: "Apple", source: .manual)
    context.insert(star)
    try context.save()
    #expect(draws(AddRecentsTab(context: log).modelContainer(container)))
    #expect(draws(AddRecipeTab(context: log).modelContainer(container)))
    for scheme in [ColorScheme.light, .dark] {
      let sheet = RecipeLogSheet(recipe: soup, day: today, slot: .dinner, onClose: {})
        .environment(\.colorScheme, scheme)
      #expect(draws(sheet.modelContainer(container)))
    }
    let gaps = RecipeLogSheet(recipe: bare, onClose: {})
    #expect(draws(gaps.modelContainer(container)))
    let action = RecipeLogAction(recipe: soup)
    #expect(draws(action.modelContainer(container)))
  }
}
