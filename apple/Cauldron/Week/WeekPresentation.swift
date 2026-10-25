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
  let weeklyComparison: WeekMacroComparison?
  let dailyTarget: MacroTargets?
  /// Days with calories planned, for the daily average.
  let daysPlanned: Int

  init(start: LocalDate, records: [PlanEntryRecord], targets: TargetsRecord? = nil) {
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
    let weekTally = tallyMacros(meals)
    self.weekTally = weekTally
    dailyTarget = targets?.macroTargets
    daysPlanned = dayTallies.values.filter { $0.totals.calories > 0 }.count
    weeklyComparison = targets.map {
      WeekMacroComparison(tally: weekTally, dailyTarget: $0.macroTargets)
    }
  }

  var isEmpty: Bool { meals.isEmpty }

  func meals(on day: LocalDate, slot: MealSlot) -> [PlanEntry] {
    meals.filter { $0.date == day && $0.slot == slot }
  }

  func tally(of day: LocalDate) -> MacroTally {
    dayTallies[day] ?? tallyMacros([])
  }

  func dailyComparison(for day: LocalDate) -> WeekMacroComparison? {
    guard let dailyTarget else { return nil }
    return WeekMacroComparison(
      tally: tally(of: day), dailyTarget: dailyTarget, days: 1)
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

  /// Comparison amounts retain a decimal so meaningful macro differences do not round to zero.
  static func comparisonRow(
    _ comparison: WeekMacroComparison, key: MacroKey, locale: Locale = .current
  ) -> String {
    let unit =
      key == .calories
      ? Copy.week.tally.macros.calories.text : Copy.week.tally.grams.text
    let remaining = comparison.remaining(for: key)
    let difference = abs(remaining)
    let differenceText =
      difference == 0
      ? comparisonAmount(0, locale: locale)
      : difference < 0.05
        ? Copy.week.tally.lessThanTenth.text
        : comparisonAmount(difference, locale: locale)
    return Copy.week.tally.comparisonRow(
      name: metricName(key), planned: comparisonAmount(comparison.planned[key], locale: locale),
      target: comparisonAmount(comparison.target[key], locale: locale), unit: unit,
      difference: differenceText, isOver: remaining < 0
    ).text
  }

  /// Compact weekly pairs retain enough precision to distinguish a small over-goal amount.
  static func compactAmount(_ value: Double, locale: Locale = .current) -> String {
    guard value.isFinite else { return 0.formatted(.number.locale(locale)) }
    return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
  }

  /// Compact color and spoken over-goal meaning follow the authoritative comparison tolerance.
  static func isOverGoal(_ comparison: WeekMacroComparison, key: MacroKey) -> Bool {
    comparison.remaining(for: key) < 0
  }

  private static func comparisonAmount(_ value: Double, locale: Locale) -> String {
    guard value.isFinite else { return 0.formatted(.number.locale(locale)) }
    return value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
  }

  static func metricName(_ key: MacroKey) -> String {
    switch key {
    case .calories: Copy.tracker.macroNames.calories.text
    case .protein: Copy.tracker.macroNames.protein.text
    case .carbs: Copy.tracker.macroNames.carbs.text
    case .fat: Copy.tracker.macroNames.fat.text
    }
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
    let missing = week.missing + week.freeText
    if missing > 0 { return Copy.week.tally.gaps(missing).text }
    return hasMacros(week) ? nil : Copy.week.tally.none.text
  }
}

/// Spreading one recipe's servings over the days that will eat them. A batch of five might be
/// dinner tonight and lunch for the next four days.
struct SpreadPlan: Equatable {
  /// The days that can be picked: the week being planned, or the seven days from the starting
  /// day on a recipe's page.
  let days: [LocalDate]
  /// The day the cook started from.
  let anchor: LocalDate
  /// The servings the batch makes: the recipe's own, or what the cook scaled it to, if either
  /// is known.
  let recipeServings: Int?
  /// The explicit batch total, even when the recipe's yield is unknown.
  private(set) var totalServings: Int
  var slot: MealSlot
  /// Servings on each picked day.
  private(set) var servings: [LocalDate: Int]

  init(days: [LocalDate], anchor: LocalDate, slot: MealSlot, recipeServings: Int?) {
    self.days = days
    self.anchor = anchor
    self.slot = slot
    self.recipeServings = recipeServings
    totalServings = recipeServings ?? 1
    servings = [anchor: 1]
  }

  /// The spread a batch starts from on a recipe's page: seven days from `anchor`, one serving a
  /// day while the batch has servings to give, and just the starting day for a batch of one
  /// serving or of no known size.
  static func batch(anchor: LocalDate, slot: MealSlot, servings: Int?) -> SpreadPlan {
    batch(anchor: anchor, days: anchor.startOfWeek().weekDays(), slot: slot, servings: servings)
  }

  static func batch(anchor: LocalDate, days: [LocalDate], slot: MealSlot, servings: Int?)
    -> SpreadPlan
  {
    var plan = SpreadPlan(days: days, anchor: anchor, slot: slot, recipeServings: servings)
    if plan.totalServings > 1 { plan.spreadOneADay() }
    return plan
  }

  /// Whether the days and servings are still the ones `batch` starts from, so nothing the cook
  /// did needs keeping.
  var isUntouched: Bool {
    self == SpreadPlan.batch(anchor: anchor, days: days, slot: slot, servings: recipeServings)
  }

  /// This spread after the cook picks another starting day. A spread the cook hasn't touched
  /// starts again from the new day; one they have is kept as it is, its days and servings
  /// moved by as many days as the start moved.
  func started(on day: LocalDate) -> SpreadPlan {
    if days.contains(day) { return started(on: day, days: days) }
    let newWeek = day.startOfWeek().weekDays()
    return started(on: day, days: newWeek)
  }

  func started(on day: LocalDate, days newDays: [LocalDate]) -> SpreadPlan {
    if isUntouched {
      return SpreadPlan.batch(anchor: day, days: newDays, slot: slot, servings: recipeServings)
    }
    let oldWeek = days.first
    let newWeek = newDays.first
    let shift =
      oldWeek.flatMap { old in newWeek.map { old.days(until: $0) } } ?? anchor.days(until: day)
    var moved = SpreadPlan(
      days: newDays, anchor: day, slot: slot,
      recipeServings: recipeServings)
    moved.totalServings = totalServings
    moved.servings = Dictionary(
      uniqueKeysWithValues: servings.map { ($0.key.adding(days: shift), $0.value) })
    return moved
  }

  /// The picked days in week order.
  var picked: [LocalDate] { days.filter { servings[$0] != nil } }
  var planned: Int { servings.values.reduce(0, +) }
  var unassigned: Int { max(0, totalServings - planned) }
  var isComplete: Bool { planned == totalServings }
  /// More servings planned than the recipe makes.
  var isOver: Bool { planned > totalServings }
  var canStir: Bool { !isOver && totalServings > 0 }

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

  mutating func setTotal(_ total: Int) {
    guard (1...WeekLimits.servings).contains(total), total >= planned else { return }
    totalServings = total
  }

  /// One serving a day from the anchor until the recipe's servings run out or the week ends.
  mutating func spreadOneADay() {
    servings = Dictionary(
      uniqueKeysWithValues: oneADay(days: days, from: anchor, servings: totalServings).map {
        ($0.date, $0.servings)
      })
  }

  /// All the recipe's servings on the anchor day.
  mutating func putAllOnAnchor() {
    servings = [anchor: min(totalServings, WeekLimits.servings)]
  }

  var summary: String {
    let total = recipeServings == nil && totalServings == 1 ? nil : totalServings
    return Copy.week.spread.planned(planned, total).text
  }
}

/// The fields of the sheet that changes one entry.
struct PlannedMealDraft: Equatable {
  var day: LocalDate
  var slot: MealSlot
  /// Nil follows the recipe's own servings.
  var servings: Int?
  var title: String

  private let original: PlanEntry
  private let allowsBatchServingEdits: Bool

  init(_ meal: PlanEntry, allowsBatchServingEdits: Bool = false) {
    original = meal
    self.allowsBatchServingEdits = allowsBatchServingEdits
    day = meal.date
    slot = meal.slot
    servings = meal.servings
    title = meal.title
  }

  /// A recipe that is live follows its own title; anything else can be renamed.
  var canRename: Bool { original.recipe == nil }
  var canEditServings: Bool { !canRename || allowsBatchServingEdits }

  /// What changed, if anything.
  var change: EntryChange? {
    var change = EntryChange()
    if day != original.date { change.day = day }
    if slot != original.slot { change.slot = slot }
    if canEditServings, servings != original.servings { change.servings = .some(servings) }
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if canRename, !name.isEmpty, name != original.title { change.title = name }
    return change.isEmpty ? nil : change
  }

  /// Whether the sheet can save: free text needs a name.
  var isValid: Bool {
    !canRename || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
