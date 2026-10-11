// The unit catalogue: dimensions, aliases and conversions (`ingredients/units.ts`).
//
// Volume units convert through millilitres and mass units through grams. Count-ish units
// (clove, can, ...) have no conversion to anything else. `pinch` and `dash` are volume units
// (1/16 and 1/8 tsp) so they scale and convert like the rest, but they are never chosen as a
// display target.

public enum UnitDimension: Sendable, Hashable {
  case volume
  case mass
  case count
}

public enum UnitSystem: Sendable, Hashable {
  case metric
  case us
  case none
}

/// The system a measure is shown in.
public enum TargetSystem: Sendable, Hashable {
  case metric
  case us
}

private let tspMl = 4.92892159375

extension UnitCode {
  public var dimension: UnitDimension {
    switch self {
    case .tsp, .tbsp, .cup, .flOz, .pint, .quart, .gallon, .ml, .l, .pinch, .dash: .volume
    case .g, .kg, .oz, .lb: .mass
    case .clove, .can, .slice, .bunch, .sprig, .stick, .piece, .package: .count
    }
  }

  public var system: UnitSystem {
    switch self {
    case .tsp, .tbsp, .cup, .flOz, .pint, .quart, .gallon, .oz, .lb, .pinch, .dash: .us
    case .ml, .l, .g, .kg: .metric
    case .clove, .can, .slice, .bunch, .sprig, .stick, .piece, .package: .none
    }
  }

  /// Millilitres per unit for volume, grams per unit for mass, 1 for count.
  public var factor: Double {
    switch self {
    case .tsp: tspMl
    case .tbsp: tspMl * 3
    case .cup: 236.5882365
    case .flOz: 29.5735295625
    case .pint: 473.176473
    case .quart: 946.352946
    case .gallon: 3785.411784
    case .ml, .g: 1
    case .l, .kg: 1000
    case .oz: 28.349523125
    case .lb: 453.59237
    case .pinch: tspMl / 16
    case .dash: tspMl / 8
    case .clove, .can, .slice, .bunch, .sprig, .stick, .piece, .package: 1
    }
  }

  public var singular: String {
    switch self {
    case .tsp: "teaspoon"
    case .tbsp: "tablespoon"
    case .cup: "cup"
    case .flOz: "fluid ounce"
    case .pint: "pint"
    case .quart: "quart"
    case .gallon: "gallon"
    case .ml: "milliliter"
    case .l: "liter"
    case .g: "gram"
    case .kg: "kilogram"
    case .oz: "ounce"
    case .lb: "pound"
    case .pinch: "pinch"
    case .dash: "dash"
    case .clove: "clove"
    case .can: "can"
    case .slice: "slice"
    case .bunch: "bunch"
    case .sprig: "sprig"
    case .stick: "stick"
    case .piece: "piece"
    case .package: "package"
    }
  }

  public var plural: String {
    switch self {
    case .tsp: "teaspoons"
    case .tbsp: "tablespoons"
    case .cup: "cups"
    case .flOz: "fluid ounces"
    case .pint: "pints"
    case .quart: "quarts"
    case .gallon: "gallons"
    case .ml: "milliliters"
    case .l: "liters"
    case .g: "grams"
    case .kg: "kilograms"
    case .oz: "ounces"
    case .lb: "pounds"
    case .pinch: "pinches"
    case .dash: "dashes"
    case .clove: "cloves"
    case .can: "cans"
    case .slice: "slices"
    case .bunch: "bunches"
    case .sprig: "sprigs"
    case .stick: "sticks"
    case .piece: "pieces"
    case .package: "packages"
    }
  }

  /// The short form `formatMeasure` uses. Count units, `pinch` and `dash` have none and spell
  /// themselves out.
  public var abbreviation: String? {
    switch self {
    case .tsp: "tsp"
    case .tbsp: "tbsp"
    case .cup: "c"
    case .flOz: "fl oz"
    case .pint: "pt"
    case .quart: "qt"
    case .gallon: "gal"
    case .ml: "ml"
    case .l: "l"
    case .g: "g"
    case .kg: "kg"
    case .oz: "oz"
    case .lb: "lb"
    case .pinch, .dash, .clove, .can, .slice, .bunch, .sprig, .stick, .piece, .package: nil
    }
  }

  /// Lowercase, dot-free aliases. Matching is case-insensitive.
  public var aliases: [String] {
    switch self {
    case .tsp: ["tsp", "tsps", "ts", "teaspoon", "teaspoons", "tspn"]
    case .tbsp: ["tbsp", "tbsps", "tbs", "tbl", "tbspn", "tablespoon", "tablespoons"]
    case .cup: ["cup", "cups", "c"]
    case .flOz: ["fl oz", "floz", "fl ounce", "fl ounces", "fluid ounce", "fluid ounces"]
    case .pint: ["pint", "pints", "pt", "pts"]
    case .quart: ["quart", "quarts", "qt", "qts"]
    case .gallon: ["gallon", "gallons", "gal", "gals"]
    case .ml: ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres"]
    case .l: ["l", "liter", "liters", "litre", "litres", "ltr"]
    case .g: ["g", "gs", "gr", "gm", "gram", "grams", "gramme", "grammes"]
    case .kg: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"]
    case .oz: ["oz", "ozs", "ounce", "ounces"]
    case .lb: ["lb", "lbs", "pound", "pounds"]
    case .pinch: ["pinch", "pinches"]
    case .dash: ["dash", "dashes"]
    case .clove: ["clove", "cloves"]
    case .can: ["can", "cans"]
    case .slice: ["slice", "slices"]
    case .bunch: ["bunch", "bunches"]
    case .sprig: ["sprig", "sprigs"]
    case .stick: ["stick", "sticks"]
    case .piece: ["piece", "pieces", "pc", "pcs"]
    case .package: ["package", "packages", "pkg", "pkgs", "packet", "packets"]
    }
  }

  /// Aliases that only match with exactly this casing ("T" vs "t").
  public var caseSensitiveAliases: [String] {
    switch self {
    case .tsp: ["t"]
    case .tbsp: ["T"]
    default: []
    }
  }
}

private enum AliasTable {
  static let exact: [String: UnitCode] = {
    var table: [String: UnitCode] = [:]
    for code in UnitCode.allCases {
      for alias in code.caseSensitiveAliases { table[alias] = code }
    }
    return table
  }()

  static let loose: [String: UnitCode] = {
    var table: [String: UnitCode] = [:]
    for code in UnitCode.allCases {
      for alias in code.aliases { table[alias] = code }
    }
    return table
  }()
}

/// Resolve a unit word ("Tbsp.", "grams", "T", "fl. oz.") to its code, or nil. Dots are
/// ignored. "T" is tbsp and "t" is tsp (case-sensitive); every other alias matches
/// case-insensitively, so "C" and "c" are both cups. Bare "oz" is weight; only "fl oz" or
/// "fluid ounce" is volume.
public func lookupUnit(_ word: String) -> UnitCode? {
  let cleaned = Scalars(word).jsTrimmed.filter { $0 != "." }.jsSpacesCollapsed.string
  if cleaned.isEmpty { return nil }
  return AliasTable.exact[cleaned] ?? AliasTable.loose[jsLowercased(cleaned)]
}

/// Convert within a dimension. Nil across dimensions (cups to grams needs a density we do not
/// have) and between different count units.
public func convert(_ quantity: Double, from: UnitCode, to: UnitCode) -> Double? {
  guard from.dimension == to.dimension else { return nil }
  if from.dimension == .count { return from == to ? quantity : nil }
  return (quantity * from.factor) / to.factor
}

/// An amount and the unit it is in.
public struct Measure: Sendable, Hashable {
  public var quantity: Double
  public var unit: UnitCode

  public init(quantity: Double, unit: UnitCode) {
    self.quantity = quantity
    self.unit = unit
  }
}

/// Express a measure in a sensible unit of `target` system.
///
/// - Volume to metric: ml below 1 l, else l. Volume to US: tsp below 1 tbsp, tbsp below 1/4
///   cup, cup below 1 quart, quart below 1 gallon, else gallon.
/// - Mass to metric: g below 1 kg, else kg. Mass to US: oz below 1 lb, else lb.
/// - Count units, `pinch` and `dash` come back unchanged. So do measures already in the target
///   system, except that small US volumes step down: a cup below 1/4 cup becomes tbsp, and a
///   tbsp below 1 tbsp becomes tsp.
public func convertForDisplay(_ quantity: Double, unit: UnitCode, target: TargetSystem) -> Measure {
  let base = quantity * unit.factor
  func to(_ code: UnitCode) -> Measure {
    Measure(quantity: base / code.factor, unit: code)
  }
  let eps = 1e-9
  if unit.dimension == .count || unit == .pinch || unit == .dash {
    return Measure(quantity: quantity, unit: unit)
  }
  if (unit.system == .metric && target == .metric) || (unit.system == .us && target == .us) {
    // Already in the target system: only step small US volumes down, so 1/8 cup reads as 2
    // tbsp and 1/2 tbsp as 1 1/2 tsp. Everything else is kept.
    if target == .us && unit == .cup && base < UnitCode.cup.factor / 4 - eps {
      return convertForDisplay(to(.tbsp).quantity, unit: .tbsp, target: .us)
    }
    if target == .us && unit == .tbsp && base < UnitCode.tbsp.factor - eps { return to(.tsp) }
    return Measure(quantity: quantity, unit: unit)
  }
  if unit.dimension == .volume {
    if target == .metric { return to(base < 1000 - eps ? .ml : .l) }
    if base < UnitCode.tbsp.factor - eps { return to(.tsp) }
    if base < UnitCode.cup.factor / 4 - eps { return to(.tbsp) }
    if base < UnitCode.quart.factor - eps { return to(.cup) }
    if base < UnitCode.gallon.factor - eps { return to(.quart) }
    return to(.gallon)
  }
  if target == .metric { return to(base < 1000 - eps ? .g : .kg) }
  return to(base < UnitCode.lb.factor - eps ? .oz : .lb)
}
