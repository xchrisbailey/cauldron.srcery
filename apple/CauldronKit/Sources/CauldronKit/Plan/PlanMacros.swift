// Running totals for the week and each day: what the planned meals add up to, from each
// recipe's per-serving calories and macros. Ported from `packages/shared/src/planMacros.ts`.

/// Servings eaten for an entry: its own count, or the whole recipe when it follows the recipe.
public func servingsOf(_ entry: PlanEntry) -> Int {
  entry.servings ?? entry.recipe?.servings ?? 1
}

public struct MacroTally: Sendable, Hashable {
  public var totals: MacroTotals
  /// Recipe meals with every macro known.
  public var counted: Int
  /// Recipe meals missing some or all macros; whatever they do have is still added.
  public var missing: Int
  /// Free-text meals, and meals whose recipe is gone: nothing to count.
  public var freeText: Int
}

/// Adds up the meals' calories and macros. Unknown values add nothing and are reported.
public func tallyMacros(_ entries: [PlanEntry]) -> MacroTally {
  var totals = MacroTotals.zero
  var counted = 0
  var missing = 0
  var freeText = 0
  for entry in entries {
    guard let recipe = entry.recipe else {
      freeText += 1
      continue
    }
    let servings = Double(servingsOf(entry))
    var known = 0
    for key in MacroKey.allCases {
      guard let value = recipe.macros[key] else { continue }
      totals[key] += value * servings
      known += 1
    }
    if known == MacroKey.allCases.count { counted += 1 } else { missing += 1 }
  }
  return MacroTally(totals: totals, counted: counted, missing: missing, freeText: freeText)
}

/// Whether any meal added anything.
public func hasMacros(_ tally: MacroTally) -> Bool {
  tally.totals.calories + tally.totals.protein + tally.totals.carbs + tally.totals.fat > 0
}

/// Servings of a recipe given to one day.
public struct DayServings: Sendable, Hashable {
  public var date: LocalDate
  public var servings: Int

  public init(date: LocalDate, servings: Int) {
    self.date = date
    self.servings = servings
  }
}

/// Days and servings for spreading one recipe over the week: one serving a day from `from`,
/// until the recipe's servings run out or the week ends. In week order.
public func oneADay(days: [LocalDate], from: LocalDate, servings: Int?) -> [DayServings] {
  let start = max(0, days.firstIndex(of: from) ?? 0)
  let count = min(servings ?? 1, days.count - start)
  guard count > 0 else { return [] }
  return days[start..<(start + count)].map { DayServings(date: $0, servings: 1) }
}
