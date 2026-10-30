#if DEBUG
  import CauldronKit
  import Foundation
  import SwiftData
  import Testing

  @testable import Cauldron

  // The numbers below come from running the TypeScript seed (`packages/db/src/seed-tracker.ts`)
  // for the same day, not from this code, so they fail if the port drifts.
  @MainActor
  @Suite("Debug seed")
  struct DebugSeedTests {
    @Test func todayUsesTheCanonicalDayKeyCalendar() throws {
      let zone = try #require(TimeZone(identifier: "Pacific/Auckland"))
      var buddhist = Calendar(identifier: .buddhist)
      buddhist.timeZone = zone
      let instant = try #require(
        DayKeyCalendar.make(timeZone: zone).date(
          from: DateComponents(year: 2026, month: 10, day: 10, hour: 23, minute: 59)))
      let expected = try #require(LocalDate("2026-10-10"))
      #expect(try DebugSeed.today(now: instant, calendar: buddhist) == expected)
    }

    // A Sunday, so the planned week is the one that ended today.
    private let today: LocalDate

    init() throws {
      today = try #require(LocalDate("2026-10-11"))
    }

    private func seeded(_ day: LocalDate? = nil) throws -> ModelContext {
      let context = ModelContext(try CauldronStore.container(.inMemory))
      try DebugSeed.populate(context, today: day ?? today)
      return context
    }

    private func recipe(_ title: String, in context: ModelContext) throws -> RecipeRecord {
      let all = try context.fetch(FetchDescriptor<RecipeRecord>())
      return try #require(all.first { $0.title.hasPrefix(title) })
    }

    // MARK: Recipes

    @Test func seedsTheFiveWebRecipes() throws {
      let context = try seeded()
      let titles = try context.fetch(FetchDescriptor<RecipeRecord>()).map(\.title).sorted()
      #expect(
        titles == [
          "Brown butter chocolate chip cookies", "Overnight oats", "Shakshuka with feta",
          "Tomato and white bean soup", "Weeknight chicken thighs with lemon and garlic",
        ])
    }

    @Test func recipeIngredientsAreParsedAndKeepTheirLine() throws {
      let context = try seeded()
      let shakshuka = try recipe("Shakshuka", in: context)
      #expect(shakshuka.ingredients.count == 12)
      let oil = shakshuka.ingredients[0]
      #expect(oil.original == "2 tbsp olive oil")
      #expect(oil.quantity == Quantity(min: 2, max: nil))
      #expect(oil.unit == .tbsp)
      #expect(oil.item == "olive oil")
      #expect(oil.itemKey == ingredientKey("olive oil"))
      let tomatoes = shakshuka.ingredients[7]
      #expect(tomatoes.unit == .can)
      #expect(tomatoes.alt == AltMeasure(quantity: Quantity(min: 28, max: nil), unit: .oz))
      #expect(shakshuka.ingredients[8].quantity == nil)
    }

    @Test func aHeadingBecomesTheSectionOfTheLinesUnderIt() throws {
      let oats = try recipe("Overnight oats", in: try seeded())
      #expect(oats.ingredients.count == 8)
      #expect(oats.ingredients[5].section == nil)
      #expect(oats.ingredients[6].section == "To serve")
      #expect(oats.ingredients[7].section == "To serve")
    }

    @Test func stepsKeepTheirTimers() throws {
      let shakshuka = try recipe("Shakshuka", in: try seeded())
      #expect(shakshuka.steps.map(\.timerSeconds) == [480, 60, 600, 360, nil])
      #expect(shakshuka.steps[4].text.hasPrefix("Scatter over the feta"))
      #expect(shakshuka.steps.allSatisfy { $0.section == nil })
    }

    @Test func recipeFactsMatchTheSource() throws {
      let context = try seeded()
      let shakshuka = try recipe("Shakshuka", in: context)
      #expect(shakshuka.servings == 4)
      #expect(shakshuka.prepMinutes == 10)
      #expect(shakshuka.cookMinutes == 25)
      #expect(shakshuka.totalMinutes == 35)
      #expect(shakshuka.macros == Macros(calories: 310, protein: 17, carbs: 18, fat: 19))
      #expect(shakshuka.macrosSource == .manual)
      #expect(shakshuka.notes == "Crusty bread for dipping is not optional in spirit.")
      let cookies = try recipe("Brown butter", in: context)
      #expect(cookies.macros == .none)
      #expect(cookies.macrosSource == nil)
      #expect(cookies.totalMinutes == 32)
    }

    @Test func tagsAreSharedAcrossRecipes() throws {
      let context = try seeded()
      let tags = try context.fetch(FetchDescriptor<TagRecord>())
      #expect(
        tags.map(\.name).sorted() == [
          "Breakfast", "Dessert", "Dinner", "Gluten-free", "Italian", "Lunch", "Middle Eastern",
          "Vegan", "Vegetarian",
        ])
      let breakfast = try #require(tags.first { $0.name == "Breakfast" })
      #expect(breakfast.kind == .meal)
      #expect(
        Set(breakfast.recipes?.map(\.title) ?? []) == ["Shakshuka with feta", "Overnight oats"])
      let vegan = try #require(tags.first { $0.name == "Vegan" })
      #expect(vegan.kind == .diet)
    }

    @Test func searchTextCoversTitleItemsAndTags() throws {
      let shakshuka = try recipe("Shakshuka", in: try seeded())
      #expect(shakshuka.searchText.contains("shakshuka with feta"))
      #expect(shakshuka.searchText.contains("olive oil"))
      #expect(shakshuka.searchText.contains("middle eastern"))
      #expect(shakshuka.searchText == shakshuka.searchText.lowercased())
    }

    // MARK: Plan

    @Test func plansTheWeekContainingToday() throws {
      let context = try seeded()
      let entries = try context.fetch(FetchDescriptor<PlanEntryRecord>())
        .sorted { ($0.dayKey, $0.slotRaw) < ($1.dayKey, $1.slotRaw) }
      #expect(
        entries.map { "\($0.dayKey) \($0.slot.rawValue) \($0.title) \($0.servings ?? 0)" } == [
          "2026-10-05 dinner Weeknight chicken thighs with lemon and garlic 4",
          "2026-10-06 lunch Tomato and white bean soup 4",
          "2026-10-07 dinner Shakshuka with feta 4",
          "2026-10-08 breakfast Overnight oats 2",
          "2026-10-10 snack Brown butter chocolate chip cookies 12",
        ])
      #expect(entries.allSatisfy { $0.recipe?.title == $0.title })
    }

    @Test func theWeekFollowsToday() throws {
      let wednesday = try #require(LocalDate("2026-10-14"))
      let context = try seeded(wednesday)
      let days = try context.fetch(FetchDescriptor<PlanEntryRecord>()).map(\.dayKey).sorted()
      #expect(days == ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-17"])
    }

    // MARK: Tracker

    @Test func weighInsMatchTheTypeScriptSeed() throws {
      let context = try seeded()
      let weighIns = try context.fetch(FetchDescriptor<WeighInRecord>())
        .sorted { $0.dayKey < $1.dayKey }
      #expect(weighIns.count == 23)
      let expected: [(String, Double)] = [
        ("2026-09-13", 74.35), ("2026-09-14", 74.07), ("2026-09-15", 73.61),
        ("2026-09-16", 74.53), ("2026-09-17", 74.19), ("2026-09-19", 73.96),
        ("2026-09-20", 73.98), ("2026-09-22", 73.81), ("2026-09-23", 73.9),
        ("2026-09-24", 73.86), ("2026-09-26", 73.88), ("2026-09-27", 73.54),
        ("2026-09-29", 73.55), ("2026-09-30", 73.35), ("2026-10-01", 73.34),
        ("2026-10-02", 73.47), ("2026-10-03", 73.02), ("2026-10-05", 72.95),
        ("2026-10-06", 72.48), ("2026-10-07", 72.68), ("2026-10-08", 72.34),
        ("2026-10-09", 73.1), ("2026-10-10", 72.37),
      ]
      #expect(weighIns.map(\.dayKey) == expected.map(\.0))
      #expect(weighIns.map(\.weightKg) == expected.map(\.1))
    }

    @Test func diaryMatchesTheTypeScriptSeed() throws {
      let context = try seeded()
      let entries = try context.fetch(FetchDescriptor<DiaryEntryRecord>())
        .sorted { (a, b) in
          let slots = MealSlot.allCases
          return (a.dayKey, slots.firstIndex(of: a.slot) ?? 0, a.position)
            < (b.dayKey, slots.firstIndex(of: b.slot) ?? 0, b.position)
        }
      #expect(entries.count == 98)
      #expect(Set(entries.map(\.dayKey)).count == 20)
      #expect(entries.reduce(0) { $0 + ($1.calories ?? 0) * $1.servings } == 34802)
      #expect(entries.allSatisfy { $0.source == .described && !$0.macrosPending })

      let first = entries[0]
      #expect(first.dayKey == "2026-09-14")
      #expect(first.slot == .breakfast)
      #expect(first.name == "Eggs")
      #expect(first.amount == "2 large")
      #expect(first.macros == Macros(calories: 143, protein: 12.5, carbs: 1, fat: 9.5))
      let lunch = entries[2]
      #expect(lunch.name == "Tomato and white bean soup")
      #expect(lunch.servings == 1.5)
      #expect(lunch.macros == Macros(calories: 260, protein: 12, carbs: 38, fat: 6))
      #expect(entries[3].name == "Weeknight chicken thighs")

      let last = entries[97]
      #expect(last.dayKey == "2026-10-10")
      #expect(last.slot == .snack)
      #expect(last.name == "Dark chocolate")
      #expect(last.servings == 1)
      #expect(entries[95].name == "Salmon")
      #expect(entries[96].name == "Roast potatoes")
      #expect(entries[96].position == 1)
    }

    @Test func historyRunsTwentyEightDaysUpToToday() throws {
      let context = try seeded()
      let days =
        try context.fetch(FetchDescriptor<WeighInRecord>()).map(\.dayKey)
        + context.fetch(FetchDescriptor<DiaryEntryRecord>()).map(\.dayKey)
      #expect(days.min() == "2026-09-13")
      #expect(days.max() == "2026-10-10")
    }

    @Test func bodyProfileAndTargets() throws {
      let context = try seeded()
      let profile = try #require(try context.current(BodyProfileRecord.self))
      #expect(profile.sex == .female)
      #expect(profile.birthDate == LocalDate("1990-05-14"))
      #expect(profile.heightCm == 168)
      #expect(profile.activity == .light)
      #expect(profile.goal == .lose)
      #expect(profile.weeklyRateKg == 0.5)
      #expect(profile.proteinPerKg == 1.8)
      #expect(profile.fatShare == 0.25)
      #expect(profile.weightUnit == .kg)
      #expect(profile.heightUnit == .cm)

      let targets = try #require(try context.current(TargetsRecord.self))
      #expect(targets.calories == 1450)
      #expect(targets.protein == 134)
      #expect(targets.carbs == 129)
      #expect(targets.fat == 45)
      #expect(!targets.caloriesOverridden)
      // Over a week ago, so the weekly check-in is due.
      #expect(targets.checkedInOn == LocalDate("2026-10-03"))
    }

    // MARK: Seeding twice

    private func counts(_ context: ModelContext) throws -> [Int] {
      [
        try context.fetchCount(FetchDescriptor<RecipeRecord>()),
        try context.fetchCount(FetchDescriptor<TagRecord>()),
        try context.fetchCount(FetchDescriptor<PlanEntryRecord>()),
        try context.fetchCount(FetchDescriptor<DiaryEntryRecord>()),
        try context.fetchCount(FetchDescriptor<WeighInRecord>()),
        try context.fetchCount(FetchDescriptor<BodyProfileRecord>()),
        try context.fetchCount(FetchDescriptor<TargetsRecord>()),
      ]
    }

    @Test func seedsAnEmptyStoreOnly() throws {
      let context = ModelContext(try CauldronStore.container(.inMemory))
      #expect(try DebugSeed.populate(context, today: today))
      let once = try counts(context)
      #expect(once == [5, 9, 5, 98, 23, 1, 1])

      #expect(try !DebugSeed.populate(context, today: today))
      #expect(try !DebugSeed.populate(context, today: today.adding(days: 3)))
      #expect(try counts(context) == once)
    }

    @Test(arguments: ["recipe", "weigh-in", "diary", "plan", "profile", "targets"])
    func leavesAStoreWithAnythingInIt(_ existing: String) throws {
      let context = ModelContext(try CauldronStore.container(.inMemory))
      switch existing {
      case "recipe": context.insert(RecipeRecord(title: "Mine"))
      case "weigh-in": context.insert(WeighInRecord(day: today, weightKg: 70))
      case "diary":
        context.insert(DiaryEntryRecord(day: today, slot: .lunch, name: "Toast", source: .manual))
      case "plan": context.insert(PlanEntryRecord(day: today, slot: .dinner, title: "Pasta"))
      case "profile": context.insert(BodyProfileRecord())
      default: context.insert(TargetsRecord(calories: 2000, protein: 100, carbs: 200, fat: 70))
      }
      try context.save()
      let before = try counts(context)

      #expect(try !DebugSeed.populate(context, today: today))
      #expect(try counts(context) == before)
    }

    // MARK: The launch switch

    @Test func theSeedArgumentFillsAnEmptyStore() throws {
      let context = ModelContext(try CauldronStore.container(.inMemory))
      let ran = try DebugSeed.populateIfRequested(
        arguments: ["Cauldron", "-seed"], mode: .local, context: context, today: today)
      #expect(ran)
      #expect(try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 5)
    }

    @Test func nothingIsSeededWithoutTheArgument() throws {
      let context = ModelContext(try CauldronStore.container(.inMemory))
      let ran = try DebugSeed.populateIfRequested(
        arguments: ["Cauldron", "-other"], mode: .local, context: context, today: today)
      #expect(!ran)
      #expect(try counts(context) == [0, 0, 0, 0, 0, 0, 0])
    }

    @Test func nothingIsSeededUnderTestEvenWhenAsked() throws {
      let context = ModelContext(try CauldronStore.container(.inMemory))
      let ran = try DebugSeed.populateIfRequested(
        arguments: ["Cauldron", "-seed"], mode: .inMemory, context: context, today: today)
      #expect(!ran)
      #expect(try counts(context) == [0, 0, 0, 0, 0, 0, 0])
    }

    @Test func launchModeIsInMemoryInThisTestRun() {
      // The app wiring leans on this: a test host never seeds from its own arguments.
      #expect(CauldronStore.launchMode == .inMemory)
    }
  }
#endif
