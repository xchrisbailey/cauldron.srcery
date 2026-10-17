import Foundation

// The small pure helpers the diary and the tracker lean on, ported from `Tracker.ts`.

/// Something that carries per-serving calories and macros.
public protocol MacroCarrying {
  var macros: Macros { get }
}

/// Something eaten in a number of servings, with the numbers for one serving.
public protocol ServedFood: MacroCarrying {
  var servings: Double { get }
}

extension DiaryEntry: ServedFood {}
extension QuickFood: ServedFood {}
extension DescribedItem: MacroCarrying {}

/// What a food adds to the day: its per-serving numbers times servings. Unknowns add nothing.
public func entryTotals(macros: Macros, servings: Double) -> MacroTotals {
  var totals = MacroTotals.zero
  for key in MacroKey.allCases { totals[key] = (macros[key] ?? 0) * servings }
  return totals
}

public func entryTotals(_ food: some ServedFood) -> MacroTotals {
  entryTotals(macros: food.macros, servings: food.servings)
}

/// The day's totals. Unknown values add nothing.
public func dayTotals(_ entries: [some ServedFood]) -> MacroTotals {
  var totals = MacroTotals.zero
  for entry in entries {
    let add = entryTotals(entry)
    for key in MacroKey.allCases { totals[key] += add[key] }
  }
  return totals
}

/// Whether any of the numbers is missing.
public func hasGaps(_ macros: Macros) -> Bool {
  MacroKey.allCases.contains { macros[$0] == nil }
}

public func hasGaps(_ food: some MacroCarrying) -> Bool {
  hasGaps(food.macros)
}

/// The key recents and favourites are matched by: the recipe, or the name and amount.
public func quickFoodKey(recipeId: RecipeId?, name: String, amount: String?) -> String {
  if let recipeId { return "recipe:\(recipeId.uuidString.lowercased())" }
  func tidy(_ text: String) -> String {
    text.jsTrimmed().lowercased()
  }
  return "food:\(tidy(name))|\(tidy(amount ?? ""))"
}

public func quickFoodKey(_ food: QuickFood) -> String {
  quickFoodKey(recipeId: food.recipeId, name: food.name, amount: food.amount)
}

public func quickFoodKey(_ entry: DiaryEntry) -> String {
  quickFoodKey(recipeId: entry.recipeId, name: entry.name, amount: entry.amount)
}
