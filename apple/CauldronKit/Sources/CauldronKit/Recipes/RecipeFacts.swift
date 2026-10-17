// Facts every client works out the same way from a recipe: how long it takes, how much to
// scale it by, and the slice of it the week shows (`recipeFacts.ts`).

/// Total time, or prep plus cook when the total isn't set.
public func recipeMinutes(totalMinutes: Int?, prepMinutes: Int?, cookMinutes: Int?) -> Int? {
  if let totalMinutes { return totalMinutes }
  if prepMinutes != nil || cookMinutes != nil { return (prepMinutes ?? 0) + (cookMinutes ?? 0) }
  return nil
}

/// How much to scale quantities by to cook `wanted` servings of a recipe that makes
/// `recipeServings`. Unchanged when either is unknown.
public func servingFactor(recipeServings: Int?, wanted: Int?) -> Double {
  guard let recipeServings, let wanted else { return 1 }
  return Double(wanted) / Double(recipeServings)
}

/// A recipe as the week shows it.
public func toPlanRecipe(
  id: RecipeId, title: String, servings: Int?, totalMinutes: Int?, prepMinutes: Int?,
  cookMinutes: Int?, photoKey: String?, macros: Macros
) -> PlanRecipe {
  PlanRecipe(
    id: id, title: title, servings: servings,
    totalMinutes: recipeMinutes(
      totalMinutes: totalMinutes, prepMinutes: prepMinutes, cookMinutes: cookMinutes),
    photoKey: photoKey, macros: macros)
}

public func toPlanRecipe(_ recipe: RecipeSummary) -> PlanRecipe {
  toPlanRecipe(
    id: recipe.id, title: recipe.title, servings: recipe.servings,
    totalMinutes: recipe.totalMinutes, prepMinutes: recipe.prepMinutes,
    cookMinutes: recipe.cookMinutes, photoKey: recipe.photoKey, macros: recipe.macros)
}

/// A card's per-serving macros as one compact line and the words a screen reader says for it.
public struct MacroLine: Sendable, Hashable {
  /// "420 kcal · 32P · 18F · 30C".
  public var text: String
  /// "Per serving: 420 kcal, 32 g protein, 18 g fat, 30 g carbs".
  public var label: String

  public init(text: String, label: String) {
    self.text = text
    self.label = label
  }
}

/// In the order a card reads them: calories, then protein, fat and carbs.
private let macroLineOrder: [MacroKey] = [.calories, .protein, .fat, .carbs]

/// A recipe's per-serving macros as one compact line ("420 kcal · 32P · 18F · 30C") and the
/// words a screen reader says for it. Unknown values are left out; nil when none are known.
public func macroLine(_ macros: Macros) -> MacroLine? {
  let known = macroLineOrder.compactMap { key in
    macros[key].map { (key: key, value: jsGroupedRounded($0)) }
  }
  if known.isEmpty { return nil }
  let copy = Copy.library.macroLine
  func line(_ key: MacroKey, _ value: String) -> String {
    switch key {
    case .calories: copy.calories(value).text
    case .protein: copy.protein(value).text
    case .fat: copy.fat(value).text
    case .carbs: copy.carbs(value).text
    }
  }
  func spoken(_ key: MacroKey, _ value: String) -> String {
    switch key {
    case .calories: copy.spoken.calories(value).text
    case .protein: copy.spoken.protein(value).text
    case .fat: copy.spoken.fat(value).text
    case .carbs: copy.spoken.carbs(value).text
    }
  }
  return MacroLine(
    text: known.map { line($0.key, $0.value) }.joined(separator: " · "),
    label: copy.spoken.label(known.map { spoken($0.key, $0.value) }.joined(separator: ", ")).text)
}

// ---------------------------------------------------------------------------
// Scaling a recipe while reading or brewing it: by servings when the recipe has them,
// otherwise by a multiplier from a fixed ladder. The recipe page steps it, hands it to brew,
// and brew reads it back.

/// One serving, or one rung of the ladder, more or fewer.
public enum ScaleStep: Int, Sendable, Hashable {
  case down = -1
  case up = 1
}

/// A value as it travels in a URL or other loosely typed parameters, before it is checked.
public enum SearchValue: Sendable, Hashable {
  case number(Double)
  case string(String)
  case bool(Bool)

  /// `Number(value)` for a number or a non-blank string, and NaN for anything else.
  fileprivate var asNumber: Double {
    switch self {
    case .number(let n): n
    case .string(let s): jsTrim(s).isEmpty ? .nan : jsNumber(s)
    case .bool: .nan
    }
  }
}

extension SearchValue: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
  ExpressibleByStringLiteral, ExpressibleByBooleanLiteral
{
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
  public init(floatLiteral value: Double) { self = .number(value) }
  public init(stringLiteral value: String) { self = .string(value) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// A scale as search parameters.
public struct ScaleSearch: Sendable, Hashable {
  public var servings: SearchValue?
  public var multiplier: SearchValue?

  public init(servings: SearchValue? = nil, multiplier: SearchValue? = nil) {
    self.servings = servings
    self.multiplier = multiplier
  }
}

public enum Scale: Sendable, Hashable {
  case servings(Int)
  case multiplier(Double)

  /// The ladder a multiplier steps along.
  public static let multipliers: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 8]

  private static let unscaled = Scale.multiplier(1)

  /// The recipe as written: its own servings, or a multiplier of 1.
  public static func initial(servings: Int?) -> Scale {
    servings.map(Scale.servings) ?? unscaled
  }

  /// The factor this scale applies to the quantities of a recipe that makes `recipeServings`.
  public func factor(recipeServings: Int?) -> Double {
    switch self {
    case .servings(let servings):
      servingFactor(recipeServings: recipeServings, wanted: servings)
    case .multiplier(let multiplier): multiplier
    }
  }

  private static func isServings(_ n: Int) -> Bool { (1...RecipeLimits.servings).contains(n) }

  private func next(_ step: ScaleStep) -> Scale? {
    switch self {
    case .servings(let servings):
      let wanted = servings + step.rawValue
      return Scale.isServings(wanted) ? .servings(wanted) : nil
    case .multiplier(let current):
      let rung =
        step == .up
        ? Scale.multipliers.first { $0 > current } : Scale.multipliers.last { $0 < current }
      return rung.map(Scale.multiplier)
    }
  }

  /// Whether there's a serving, or a rung of the ladder, further that way.
  public func canStep(_ step: ScaleStep) -> Bool { next(step) != nil }

  /// One serving, or one rung of the ladder, more or fewer; the same scale at either end.
  public func stepped(_ step: ScaleStep) -> Scale { next(step) ?? self }

  /// The search params for this scale; none when it's a multiplier of 1.
  public var search: ScaleSearch {
    switch self {
    case .servings(let servings): ScaleSearch(servings: .number(Double(servings)))
    case .multiplier(let multiplier) where multiplier != 1:
      ScaleSearch(multiplier: .number(multiplier))
    case .multiplier: ScaleSearch()
    }
  }

  /// The scale in search params, held to the bounds `stepped` keeps: whole servings up to the
  /// recipe limit, or a multiplier on the ladder. Anything else reads as unscaled.
  public init(search: ScaleSearch) {
    if let servings = search.servings?.asNumber, servings == servings.rounded(.towardZero),
      servings >= 1, servings <= Double(RecipeLimits.servings)
    {
      self = .servings(Int(servings))
    } else if let multiplier = search.multiplier?.asNumber, Scale.multipliers.contains(multiplier) {
      self = .multiplier(multiplier)
    } else {
      self = Scale.unscaled
    }
  }
}
