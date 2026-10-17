/// The four numbers the app tracks.
public enum MacroKey: String, Sendable, Hashable, Codable, CaseIterable {
  case calories
  case protein
  case carbs
  case fat
}

/// Calories and macros for one serving, as written on the recipe or entered by hand. Any of
/// them can be unknown.
public struct Macros: Sendable, Hashable, Codable {
  public var calories: Double?
  public var protein: Double?
  public var carbs: Double?
  public var fat: Double?

  public init(
    calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil
  ) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }

  /// Nothing known (`noMacros` in the reference).
  public static let none = Macros()

  public subscript(key: MacroKey) -> Double? {
    switch key {
    case .calories: calories
    case .protein: protein
    case .carbs: carbs
    case .fat: fat
    }
  }
}

/// Calories and macros added up, with unknowns counting as nothing.
public struct MacroTotals: Sendable, Hashable, Codable {
  public var calories: Double
  public var protein: Double
  public var carbs: Double
  public var fat: Double

  public init(calories: Double, protein: Double, carbs: Double, fat: Double) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }

  public static let zero = MacroTotals(calories: 0, protein: 0, carbs: 0, fat: 0)

  public subscript(key: MacroKey) -> Double {
    get {
      switch key {
      case .calories: calories
      case .protein: protein
      case .carbs: carbs
      case .fat: fat
      }
    }
    set {
      switch key {
      case .calories: calories = newValue
      case .protein: protein = newValue
      case .carbs: carbs = newValue
      case .fat: fat = newValue
      }
    }
  }
}
