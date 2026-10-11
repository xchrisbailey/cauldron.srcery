import CauldronKit
import Foundation

// What the week screens print, worked out apart from the views so it can be tested.

/// The seven days of a week as the screens read them: the meals in order, and the tallies for
/// the week and for each day.
struct WeekSnapshot {
  let days: [LocalDate]
  /// Every readable entry in the week, in day, meal and position order.
  let meals: [PlanEntry]
  let weekTally: MacroTally
  let dayTallies: [LocalDate: MacroTally]
  /// Days with calories planned, for the daily average.
  let daysPlanned: Int

  init(start: LocalDate, records: [PlanEntryRecord]) {
    let days = start.weekDays()
    let inWeek = Set(days)
    let meals = WeekPlan.ordered(records).compactMap(WeekPlan.meal).filter {
      inWeek.contains($0.date)
    }
    let dayTallies = Dictionary(
      uniqueKeysWithValues: days.map { day in (day, tallyMacros(meals.filter { $0.date == day })) })
    self.days = days
    self.meals = meals
    self.dayTallies = dayTallies
    weekTally = tallyMacros(meals)
    daysPlanned = dayTallies.values.filter { $0.totals.calories > 0 }.count
  }

  var isEmpty: Bool { meals.isEmpty }

  func meals(on day: LocalDate, slot: MealSlot) -> [PlanEntry] {
    meals.filter { $0.date == day && $0.slot == slot }
  }

  func tally(of day: LocalDate) -> MacroTally {
    dayTallies[day] ?? tallyMacros([])
  }
}

/// What a meal's card says.
struct MealCard: Equatable {
  let title: String
  /// "45 min · 4 servings · 1,680 kcal"; nil for a meal that isn't a recipe.
  let detail: String?
  let isRecipe: Bool

  init(_ meal: PlanEntry) {
    title = meal.recipe?.title ?? meal.title
    isRecipe = meal.recipe != nil
    guard let recipe = meal.recipe else {
      detail = nil
      return
    }
    if meal.brewed {
      detail = Copy.week.brewed.text
      return
    }
    let servings = meal.servings ?? recipe.servings
    let parts: [String?] = [
      recipe.totalMinutes.flatMap { $0 > 0 ? formatTimer($0 * 60) : nil },
      servings.map { Copy.week.spread.servingsOn($0).text },
      recipe.macros.calories.map {
        "\(WeekFigures.whole($0 * Double(servingsOf(meal)))) \(Copy.week.tally.macros.calories.text)"
      },
    ]
    let joined = parts.compactMap { $0 }.joined(separator: " · ")
    detail = joined.isEmpty ? nil : joined
  }
}

/// Numbers as the tally prints them.
enum WeekFigures {
  /// Rounded as `Math.round` does (halves go up) and grouped for the locale: "1,680".
  static func whole(_ value: Double, locale: Locale = .current) -> String {
    guard value.isFinite else { return "0" }
    return Int((value + 0.5).rounded(.down)).formatted(.number.locale(locale))
  }

  /// Calories from each macro: 4 per gram of protein and carbs, 9 per gram of fat.
  static let kcalPerGram: [MacroKey: Double] = [.protein: 4, .carbs: 4, .fat: 9]

  static let gramKeys: [MacroKey] = [.protein, .carbs, .fat]

  /// Each macro's share of the calories they add up to, for the split bar. Empty when there
  /// is nothing to split.
  static func split(_ totals: MacroTotals) -> [(key: MacroKey, share: Double)] {
    let calories = gramKeys.map { totals[$0] * (kcalPerGram[$0] ?? 0) }
    let sum = calories.reduce(0, +)
    guard sum > 0 else { return [] }
    return zip(gramKeys, calories).map { ($0, $1 / sum) }
  }

  /// "≈ 1,180 kcal a day", once more than one day has calories planned.
  static func average(of tally: MacroTally, daysPlanned: Int, locale: Locale = .current) -> String?
  {
    guard hasMacros(tally), daysPlanned > 1 else { return nil }
    let kcal = Copy.week.tally.macros.calories.text
    return
      "≈ \(whole(tally.totals.calories / Double(daysPlanned), locale: locale)) \(kcal) \(Copy.week.tally.perDay.text)"
  }

  /// The line under the tally: how to fill it when it is empty, or how many meals are only
  /// partly counted.
  static func note(week: MacroTally, day: MacroTally?) -> String? {
    guard hasMacros(week) else { return Copy.week.tally.none.text }
    let missing = day?.missing ?? week.missing
    return missing > 0 ? Copy.week.tally.gaps(missing).text : nil
  }
}

/// Spreading one recipe's servings over the days that will eat them. A batch of five might be
/// dinner tonight and lunch for the next four days.
struct SpreadPlan: Equatable {
  /// The week being planned.
  let days: [LocalDate]
  /// The day the cook started from.
  let anchor: LocalDate
  /// The recipe's own servings, if it has any.
  let recipeServings: Int?
  var slot: MealSlot
  /// Servings on each picked day.
  private(set) var servings: [LocalDate: Int]

  init(days: [LocalDate], anchor: LocalDate, slot: MealSlot, recipeServings: Int?) {
    self.days = days
    self.anchor = anchor
    self.slot = slot
    self.recipeServings = recipeServings
    servings = [anchor: 1]
  }

  /// The picked days in week order.
  var picked: [LocalDate] { days.filter { servings[$0] != nil } }
  var planned: Int { servings.values.reduce(0, +) }
  /// More servings planned than the recipe makes.
  var isOver: Bool { recipeServings.map { planned > $0 } ?? false }
  var canStir: Bool { !picked.isEmpty }

  /// The entries to add, in week order.
  var entries: [DayServings] {
    picked.compactMap { day in servings[day].map { DayServings(date: day, servings: $0) } }
  }

  func servings(on day: LocalDate) -> Int? { servings[day] }

  mutating func toggle(_ day: LocalDate) {
    servings[day] = servings[day] == nil ? 1 : nil
  }

  /// One serving more or fewer on a day; the last one off drops the day.
  mutating func step(_ day: LocalDate, by amount: Int) {
    let next = (servings[day] ?? 0) + amount
    servings[day] = next <= 0 ? nil : min(next, WeekLimits.servings)
  }

  /// One serving a day from the anchor until the recipe's servings run out or the week ends.
  mutating func spreadOneADay() {
    servings = Dictionary(
      uniqueKeysWithValues: oneADay(days: days, from: anchor, servings: recipeServings).map {
        ($0.date, $0.servings)
      })
  }

  /// All the recipe's servings on the anchor day.
  mutating func putAllOnAnchor() {
    servings = [anchor: min(max(1, recipeServings ?? 1), WeekLimits.servings)]
  }

  var summary: String {
    canStir
      ? Copy.week.spread.planned(planned, recipeServings).text : Copy.week.spread.pickADay.text
  }
}

/// The fields of the sheet that changes one entry.
struct EntryDraft: Equatable {
  var day: LocalDate
  var slot: MealSlot
  /// Nil follows the recipe's own servings.
  var servings: Int?
  var title: String

  private let original: PlanEntry

  init(_ meal: PlanEntry) {
    original = meal
    day = meal.date
    slot = meal.slot
    servings = meal.servings
    title = meal.title
  }

  /// A recipe that is live follows its own title; anything else can be renamed.
  var canRename: Bool { original.recipe == nil }

  /// What changed, if anything.
  var change: EntryChange? {
    var change = EntryChange()
    if day != original.date { change.day = day }
    if slot != original.slot { change.slot = slot }
    if !canRename, servings != original.servings { change.servings = .some(servings) }
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if canRename, !name.isEmpty, name != original.title { change.title = name }
    return change.isEmpty ? nil : change
  }

  /// Whether the sheet can save: free text needs a name.
  var isValid: Bool {
    !canRename || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
