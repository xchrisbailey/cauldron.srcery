/// Where a diary entry came from: described in words, a recipe, or typed in by hand.
public enum DiarySource: String, Sendable, Hashable, Codable, CaseIterable {
  case described
  case recipe
  case manual
}

public enum Sex: String, Sendable, Hashable, Codable, CaseIterable {
  case female
  case male
  case unspecified
}

public enum ActivityLevel: String, Sendable, Hashable, Codable, CaseIterable {
  case sedentary
  case light
  case moderate
  case active
  case veryActive
}

public enum Goal: String, Sendable, Hashable, Codable, CaseIterable {
  case lose
  case maintain
  case gain
}

public enum WeightUnit: String, Sendable, Hashable, Codable, CaseIterable {
  case kg
  case lb
}

public enum HeightUnit: String, Sendable, Hashable, Codable, CaseIterable {
  case cm
  case ftin
}

/// The numeric limits the tracker schemas enforced (`TRACKER_LIMITS` in `Tracker.ts`). The
/// calculator and the weight and check-in maths clamp to them.
public enum TrackerLimits {
  public static let name = RecipeLimits.title
  public static let amount = 100
  /// Servings on one entry. Fractions are fine: half a portion is 0.5.
  public static let servings = 100
  /// Entries on one day.
  public static let perDay = 100
  /// Entries in one batch add, such as one described meal or a copied day.
  public static let batch = 100
  /// The longest range one read may cover: a year and a day, for leap years.
  public static let rangeDays = 367
  /// Stored in kilograms.
  public static let weightKg: ClosedRange<Double> = 20...400
  public static let heightCm: ClosedRange<Double> = 100...250
  /// Kilograms a week to lose or gain.
  public static let weeklyRateKg: ClosedRange<Double> = 0...1
  public static let proteinPerKg: ClosedRange<Double> = 1.2...3
  public static let fatShare: ClosedRange<Double> = 0.2...0.4
  /// Daily targets.
  public static let calories: ClosedRange<Double> = 800...10_000
  public static let grams: ClosedRange<Double> = 0...1000
}

/// What was actually eaten. Diary entries copy their calories and macros when logged, so
/// editing or banishing a recipe later never rewrites a logged day.
public struct DiaryEntry: Sendable, Hashable, Codable {
  public var id: DiaryEntryId
  public var date: LocalDate
  public var slot: MealSlot
  public var name: String
  /// What was eaten, in words: "2 large", "1 slice".
  public var amount: String?
  public var servings: Double
  /// Per serving, as copied when logged. Unknowns stay nil.
  public var macros: Macros
  public var source: DiarySource
  /// The recipe it was logged from, while that recipe exists.
  public var recipeId: RecipeId?
  /// Order within the day's slot, from 0.
  public var position: Int

  public init(
    id: DiaryEntryId, date: LocalDate, slot: MealSlot, name: String, amount: String?,
    servings: Double, macros: Macros, source: DiarySource, recipeId: RecipeId?, position: Int
  ) {
    self.id = id
    self.date = date
    self.slot = slot
    self.name = name
    self.amount = amount
    self.servings = servings
    self.macros = macros
    self.source = source
    self.recipeId = recipeId
    self.position = position
  }
}

/// The body details the calculator turns into daily targets. Everything is stored in metric.
public struct BodyProfile: Sendable, Hashable, Codable {
  public var sex: Sex
  public var birthDate: LocalDate
  public var heightCm: Double
  public var activity: ActivityLevel
  public var goal: Goal
  /// Kilograms a week; ignored when maintaining.
  public var weeklyRateKg: Double
  /// Grams of protein per kilogram of bodyweight.
  public var proteinPerKg: Double
  /// Share of calories from fat, 0.2 to 0.4.
  public var fatShare: Double
  /// How weights and heights are shown.
  public var weightUnit: WeightUnit
  public var heightUnit: HeightUnit

  public init(
    sex: Sex, birthDate: LocalDate, heightCm: Double, activity: ActivityLevel, goal: Goal,
    weeklyRateKg: Double, proteinPerKg: Double, fatShare: Double, weightUnit: WeightUnit,
    heightUnit: HeightUnit
  ) {
    self.sex = sex
    self.birthDate = birthDate
    self.heightCm = heightCm
    self.activity = activity
    self.goal = goal
    self.weeklyRateKg = weeklyRateKg
    self.proteinPerKg = proteinPerKg
    self.fatShare = fatShare
    self.weightUnit = weightUnit
    self.heightUnit = heightUnit
  }
}

/// Which targets were typed in by hand rather than calculated.
public struct TargetOverrides: Sendable, Hashable, Codable {
  public var calories: Bool
  public var protein: Bool
  public var carbs: Bool
  public var fat: Bool

  public init(calories: Bool, protein: Bool, carbs: Bool, fat: Bool) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }
}

public struct Targets: Sendable, Hashable, Codable {
  public var calories: Int
  public var protein: Int
  public var carbs: Int
  public var fat: Int
  public var overridden: TargetOverrides
  /// The day of the last weekly check-in.
  public var checkedInOn: LocalDate?

  public init(
    calories: Int, protein: Int, carbs: Int, fat: Int, overridden: TargetOverrides,
    checkedInOn: LocalDate?
  ) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
    self.overridden = overridden
    self.checkedInOn = checkedInOn
  }
}

/// The profile and targets together; both nil until the calculator has been run.
public struct TrackerSettings: Sendable, Hashable, Codable {
  public var profile: BodyProfile?
  public var targets: Targets?

  public init(profile: BodyProfile?, targets: Targets?) {
    self.profile = profile
    self.targets = targets
  }
}

public struct WeighIn: Sendable, Hashable, Codable {
  public var date: LocalDate
  public var weightKg: Double

  public init(date: LocalDate, weightKg: Double) {
    self.date = date
    self.weightKg = weightKg
  }
}

/// One day as the tracker shows it.
public struct DiaryDay: Sendable, Hashable, Codable {
  public var date: LocalDate
  /// By slot (breakfast to snack) and position.
  public var entries: [DiaryEntry]
  public var totals: MacroTotals
  public var targets: Targets?
  public var weighIn: WeighIn?

  public init(
    date: LocalDate, entries: [DiaryEntry], totals: MacroTotals, targets: Targets?,
    weighIn: WeighIn?
  ) {
    self.date = date
    self.entries = entries
    self.totals = totals
    self.targets = targets
    self.weighIn = weighIn
  }
}

/// What one day added up to, for averages and the weekly check-in.
public struct IntakeDay: Sendable, Hashable, Codable {
  public var date: LocalDate
  public var entries: Int
  public var totals: MacroTotals

  public init(date: LocalDate, entries: Int, totals: MacroTotals) {
    self.date = date
    self.entries = entries
    self.totals = totals
  }
}

/// One food the model found, with its amount and numbers for that amount. Numbers are nil
/// when the model couldn't say, or the item isn't food.
public struct DescribedItem: Sendable, Hashable, Codable {
  public var name: String
  public var amount: String?
  public var macros: Macros

  public init(name: String, amount: String?, macros: Macros) {
    self.name = name
    self.amount = amount
    self.macros = macros
  }
}

public struct MealEstimate: Sendable, Hashable, Codable {
  public var items: [DescribedItem]

  public init(items: [DescribedItem]) {
    self.items = items
  }
}

/// Something logged before, as it was last logged: what a one-tap re-log copies.
public struct QuickFood: Sendable, Hashable, Codable {
  public var name: String
  public var amount: String?
  /// Servings the last time it was logged.
  public var servings: Double
  /// Per serving.
  public var macros: Macros
  public var source: DiarySource
  public var recipeId: RecipeId?

  public init(
    name: String, amount: String?, servings: Double, macros: Macros, source: DiarySource,
    recipeId: RecipeId?
  ) {
    self.name = name
    self.amount = amount
    self.servings = servings
    self.macros = macros
    self.source = source
    self.recipeId = recipeId
  }
}

public struct Favourite: Sendable, Hashable, Codable {
  public var id: FavouriteId
  public var food: QuickFood

  public init(id: FavouriteId, food: QuickFood) {
    self.id = id
    self.food = food
  }
}

public struct RecentFood: Sendable, Hashable, Codable {
  public var food: QuickFood
  /// Times logged in the recent window.
  public var count: Int
  public var lastLoggedOn: LocalDate
  /// The latest entry it was logged as, for starring it.
  public var lastEntryId: DiaryEntryId

  public init(food: QuickFood, count: Int, lastLoggedOn: LocalDate, lastEntryId: DiaryEntryId) {
    self.food = food
    self.count = count
    self.lastLoggedOn = lastLoggedOn
    self.lastEntryId = lastEntryId
  }
}

public struct QuickFoods: Sendable, Hashable, Codable {
  public var favourites: [Favourite]
  /// Most often logged first, then most recent. Starred foods are left out.
  public var recents: [RecentFood]

  public init(favourites: [Favourite], recents: [RecentFood]) {
    self.favourites = favourites
    self.recents = recents
  }
}
