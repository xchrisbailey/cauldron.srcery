#if DEBUG
  import CauldronKit
  import Foundation
  import SwiftData

  /// Demo data for a debug build: five recipes, a planned week, and four weeks of diary and
  /// weigh-ins, ported from `bun run --cwd packages/db seed`. It is not compiled into release
  /// builds, and it runs only when asked for, with the `-seed` launch argument.
  enum DebugSeed {
    static let launchArgument = "-seed"

    /// Fills an empty store, and returns whether it did. A store with anything in it is left
    /// alone, so running this twice, or on real data, never adds a second copy.
    @discardableResult
    static func populate(_ context: ModelContext, today: LocalDate) throws -> Bool {
      guard try isEmpty(context) else { return false }
      let recipes = insertRecipes(into: context)
      insertPlan(for: today, recipes: recipes, into: context)
      try insertTracker(endingOn: today, into: context)
      try context.save()
      return true
    }

    /// Seeds when `arguments` carry `-seed`, and only into a store kept on this device: never
    /// under test (`launchMode` is `.inMemory`), and never into a synced store, where demo
    /// data would go up to iCloud.
    @discardableResult
    static func populateIfRequested(
      arguments: [String], mode: CauldronStore.Mode, context: ModelContext, today: LocalDate
    ) throws -> Bool {
      guard mode == .local, arguments.contains(launchArgument) else { return false }
      return try populate(context, today: today)
    }

    struct SeedError: Error {
      var message: String
    }

    /// Today's Gregorian civil day in the cook's time zone.
    static func today(
      now: Date = .now, calendar: Calendar = DayKeyCalendar.current
    ) throws -> LocalDate {
      guard let today = LocalDate(now, in: calendar) else {
        throw SeedError(message: "There is no calendar day for now.")
      }
      return today
    }

    private static func isEmpty(_ context: ModelContext) throws -> Bool {
      try context.fetchCount(FetchDescriptor<RecipeRecord>()) == 0
        && context.fetchCount(FetchDescriptor<PlanEntryRecord>()) == 0
        && context.fetchCount(FetchDescriptor<DiaryEntryRecord>()) == 0
        && context.fetchCount(FetchDescriptor<WeighInRecord>()) == 0
        && context.fetchCount(FetchDescriptor<BodyProfileRecord>()) == 0
        && context.fetchCount(FetchDescriptor<TargetsRecord>()) == 0
    }

    // MARK: Recipes

    private static func insertRecipes(into context: ModelContext) -> [RecipeRecord] {
      var tags: [String: TagRecord] = [:]
      return recipes.map { seed in
        let record = RecipeRecord(title: seed.title)
        record.summary = seed.description
        record.servings = seed.servings
        record.prepMinutes = seed.prepMinutes
        record.cookMinutes = seed.cookMinutes
        record.totalMinutes = seed.prepMinutes + seed.cookMinutes
        record.notes = seed.notes
        if let macros = seed.macros {
          record.macros = macros
          record.macrosSource = .manual
        }
        record.ingredients = readIngredientBlock(seed.ingredients).map { line in
          Ingredient(
            section: line.section, quantity: line.quantity, unit: line.unit, item: line.item,
            note: line.note, optional: line.optional, alt: line.alt, original: line.original,
            itemKey: ingredientKey(line.item))
        }
        record.steps = seed.steps.map {
          Step(section: nil, text: $0.text, timerSeconds: $0.timerSeconds)
        }
        context.insert(record)

        record.tags = seed.tags.map { tag in
          let key = tag.name.lowercased()
          if let existing = tags[key] { return existing }
          let created = TagRecord(name: tag.name, kind: tag.kind)
          context.insert(created)
          tags[key] = created
          return created
        }
        record.refreshSearchText()
        return record
      }
    }

    // MARK: Plan

    /// Recipe (an index into `recipes`), day of the week from its first day, slot and servings.
    private static let week: [(recipe: Int, day: Int, slot: MealSlot, servings: Int)] = [
      (1, 0, .dinner, 4),
      (3, 1, .lunch, 4),
      (0, 2, .dinner, 4),
      (2, 3, .breakfast, 2),
      (4, 5, .snack, 12),
    ]

    private static func insertPlan(
      for today: LocalDate, recipes: [RecipeRecord], into context: ModelContext
    ) {
      // The store is empty, so it has no preference: the week starts on the standard day, as the
      // Week section will show it.
      let first = today.startOfWeek(startingOn: .standard)
      for entry in week {
        let recipe = recipes[entry.recipe]
        let planned = PlanEntryRecord(
          day: first.adding(days: entry.day), slot: entry.slot, title: recipe.title,
          servings: entry.servings)
        context.insert(planned)
        planned.recipe = recipe
      }
    }

    // MARK: Tracker

    private static func insertTracker(endingOn today: LocalDate, into context: ModelContext) throws
    {
      let start = today.adding(days: -SeedTracker.days)
      guard let birthDate = LocalDate("1990-05-14") else {
        throw SeedError(message: "The seed's birth date is not a day.")
      }

      let profile = BodyProfileRecord()
      profile.sex = .female
      profile.birthDate = birthDate
      profile.heightCm = 168
      profile.activity = .light
      profile.goal = .lose
      profile.weeklyRateKg = 0.5
      profile.proteinPerKg = 1.8
      profile.fatShare = 0.25
      profile.weightUnit = .kg
      profile.heightUnit = .cm
      context.insert(profile)

      let result = calculateTargets(
        CalculatorInput(
          sex: profile.sex, birthDate: birthDate, heightCm: 168, weightKg: SeedTracker.startKg,
          activity: profile.activity, goal: profile.goal, weeklyRateKg: profile.weeklyRateKg,
          proteinPerKg: profile.proteinPerKg, fatShare: profile.fatShare, today: start))
      let targets = TargetsRecord(
        calories: result.targets.calories, protein: result.targets.protein,
        carbs: result.targets.carbs, fat: result.targets.fat)
      // Last checked in over a week ago, so the weekly check-in is due.
      targets.checkedInOn = today.adding(days: -8)
      context.insert(targets)

      let history = SeedTracker.history(endingOn: today)
      for weight in history.weights {
        context.insert(WeighInRecord(day: weight.day, weightKg: weight.kg))
      }
      for meal in history.meals {
        let entry = DiaryEntryRecord(
          day: meal.day, slot: meal.slot, name: meal.food.name, servings: meal.servings,
          source: .described)
        entry.amount = meal.food.amount
        entry.position = meal.position
        entry.macros = Macros(
          calories: meal.food.calories, protein: meal.food.protein, carbs: meal.food.carbs,
          fat: meal.food.fat)
        context.insert(entry)
      }
    }
  }
#endif
