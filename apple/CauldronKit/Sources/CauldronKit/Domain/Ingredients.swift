/// Normalized unit code (`UNIT_CODES` in `ingredients/units.ts`). The raw value is the code
/// the TypeScript stored, such as `fl_oz`.
public enum UnitCode: String, Sendable, Hashable, Codable, CaseIterable {
  case tsp
  case tbsp
  case cup
  case flOz = "fl_oz"
  case pint
  case quart
  case gallon
  case ml
  case l
  case g
  case kg
  case oz
  case lb
  case pinch
  case dash
  case clove
  case can
  case slice
  case bunch
  case sprig
  case stick
  case piece
  case `package`
}

/// A quantity: a single amount (`max` nil) or a range from `min` to `max` (`max >= min`).
///
/// The initialiser doesn't check anything, so parsing and scaling can build values freely;
/// `isValid` is the schema's rule, for checking at a boundary.
public struct Quantity: Sendable, Hashable, Codable {
  public var min: Double
  public var max: Double?

  public init(min: Double, max: Double?) {
    self.min = min
    self.max = max
  }

  /// Finite amounts of at least 0, and a range whose end is not before its start.
  public var isValid: Bool {
    guard min.isFinite, min >= 0 else { return false }
    guard let max else { return true }
    return max.isFinite && max >= min
  }
}

/// A second measure for the same ingredient, e.g. the "(190g)" in "1 1/2 cups (190g) flour".
public struct AltMeasure: Sendable, Hashable, Codable {
  public var quantity: Quantity
  public var unit: UnitCode

  public init(quantity: Quantity, unit: UnitCode) {
    self.quantity = quantity
    self.unit = unit
  }
}

/// What the ingredient line parser produces from one line.
public struct ParsedIngredient: Sendable, Hashable, Codable {
  public var quantity: Quantity?
  public var unit: UnitCode?
  public var item: String
  public var note: String?
  public var optional: Bool
  public var alt: AltMeasure?
  /// The line exactly as written.
  public var original: String

  public init(
    quantity: Quantity?, unit: UnitCode?, item: String, note: String?, optional: Bool,
    alt: AltMeasure?, original: String
  ) {
    self.quantity = quantity
    self.unit = unit
    self.item = item
    self.note = note
    self.optional = optional
    self.alt = alt
    self.original = original
  }

  /// Whether every quantity in it passes `Quantity.isValid`.
  public var isValid: Bool {
    (quantity?.isValid ?? true) && (alt?.quantity.isValid ?? true)
  }
}

/// An ingredient as a saved recipe holds it: structured, never just a free-text blob.
public struct Ingredient: Sendable, Hashable, Codable {
  /// Heading this line sits under, e.g. "For the sauce".
  public var section: String?
  public var quantity: Quantity?
  public var unit: UnitCode?
  public var item: String
  public var note: String?
  public var optional: Bool
  public var alt: AltMeasure?
  /// The line exactly as written.
  public var original: String
  /// Normalized merge key (see `ingredientKey`).
  public var itemKey: String

  public init(
    section: String?, quantity: Quantity?, unit: UnitCode?, item: String, note: String?,
    optional: Bool, alt: AltMeasure?, original: String, itemKey: String
  ) {
    self.section = section
    self.quantity = quantity
    self.unit = unit
    self.item = item
    self.note = note
    self.optional = optional
    self.alt = alt
    self.original = original
    self.itemKey = itemKey
  }
}
