/**
 * Unit catalog: normalized codes, dimensions, aliases and conversions.
 *
 * Volume units convert through millilitres and mass units through grams.
 * Count-ish units (clove, can, ...) have no conversion to anything else.
 * `pinch` and `dash` are volume units (1/16 and 1/8 tsp) so they scale and
 * convert like the rest, but they are never chosen as a display target.
 */

export const UNIT_CODES = [
  "tsp",
  "tbsp",
  "cup",
  "fl_oz",
  "pint",
  "quart",
  "gallon",
  "ml",
  "l",
  "g",
  "kg",
  "oz",
  "lb",
  "pinch",
  "dash",
  "clove",
  "can",
  "slice",
  "bunch",
  "sprig",
  "stick",
  "piece",
  "package",
] as const;

type Code = (typeof UNIT_CODES)[number];

export type Dimension = "volume" | "mass" | "count";
export type UnitSystem = "metric" | "us" | "none";
export type TargetSystem = "metric" | "us";

export interface UnitDef {
  readonly code: Code;
  readonly dimension: Dimension;
  readonly system: UnitSystem;
  /** Millilitres per unit for volume, grams per unit for mass, 1 for count. */
  readonly factor: number;
  readonly singular: string;
  readonly plural: string;
  /** Short form used by `formatMeasure`; count units spell themselves out. */
  readonly abbr?: string;
  /** Lowercase, dot-free aliases. Matching is case-insensitive. */
  readonly aliases: readonly string[];
  /** Aliases that only match with exactly this casing ("T" vs "t"). */
  readonly caseSensitiveAliases?: readonly string[];
}

const TSP_ML = 4.92892159375;

export const UNITS: Readonly<Record<Code, UnitDef>> = {
  tsp: {
    code: "tsp",
    dimension: "volume",
    system: "us",
    factor: TSP_ML,
    singular: "teaspoon",
    plural: "teaspoons",
    abbr: "tsp",
    aliases: ["tsp", "tsps", "teaspoon", "teaspoons", "tspn"],
    caseSensitiveAliases: ["t"],
  },
  tbsp: {
    code: "tbsp",
    dimension: "volume",
    system: "us",
    factor: TSP_ML * 3,
    singular: "tablespoon",
    plural: "tablespoons",
    abbr: "tbsp",
    aliases: ["tbsp", "tbsps", "tbs", "tbl", "tbspn", "tablespoon", "tablespoons"],
    caseSensitiveAliases: ["T"],
  },
  cup: {
    code: "cup",
    dimension: "volume",
    system: "us",
    factor: 236.5882365,
    singular: "cup",
    plural: "cups",
    abbr: "c",
    aliases: ["cup", "cups", "c"],
  },
  fl_oz: {
    code: "fl_oz",
    dimension: "volume",
    system: "us",
    factor: 29.5735295625,
    singular: "fluid ounce",
    plural: "fluid ounces",
    abbr: "fl oz",
    aliases: ["fl oz", "floz", "fl ounce", "fl ounces", "fluid ounce", "fluid ounces"],
  },
  pint: {
    code: "pint",
    dimension: "volume",
    system: "us",
    factor: 473.176473,
    singular: "pint",
    plural: "pints",
    abbr: "pt",
    aliases: ["pint", "pints", "pt", "pts"],
  },
  quart: {
    code: "quart",
    dimension: "volume",
    system: "us",
    factor: 946.352946,
    singular: "quart",
    plural: "quarts",
    abbr: "qt",
    aliases: ["quart", "quarts", "qt", "qts"],
  },
  gallon: {
    code: "gallon",
    dimension: "volume",
    system: "us",
    factor: 3785.411784,
    singular: "gallon",
    plural: "gallons",
    abbr: "gal",
    aliases: ["gallon", "gallons", "gal", "gals"],
  },
  ml: {
    code: "ml",
    dimension: "volume",
    system: "metric",
    factor: 1,
    singular: "milliliter",
    plural: "milliliters",
    abbr: "ml",
    aliases: ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres"],
  },
  l: {
    code: "l",
    dimension: "volume",
    system: "metric",
    factor: 1000,
    singular: "liter",
    plural: "liters",
    abbr: "l",
    aliases: ["l", "liter", "liters", "litre", "litres", "ltr"],
  },
  g: {
    code: "g",
    dimension: "mass",
    system: "metric",
    factor: 1,
    singular: "gram",
    plural: "grams",
    abbr: "g",
    aliases: ["g", "gs", "gr", "gm", "gram", "grams", "gramme", "grammes"],
  },
  kg: {
    code: "kg",
    dimension: "mass",
    system: "metric",
    factor: 1000,
    singular: "kilogram",
    plural: "kilograms",
    abbr: "kg",
    aliases: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"],
  },
  oz: {
    code: "oz",
    dimension: "mass",
    system: "us",
    factor: 28.349523125,
    singular: "ounce",
    plural: "ounces",
    abbr: "oz",
    aliases: ["oz", "ozs", "ounce", "ounces"],
  },
  lb: {
    code: "lb",
    dimension: "mass",
    system: "us",
    factor: 453.59237,
    singular: "pound",
    plural: "pounds",
    abbr: "lb",
    aliases: ["lb", "lbs", "pound", "pounds"],
  },
  pinch: {
    code: "pinch",
    dimension: "volume",
    system: "us",
    factor: TSP_ML / 16,
    singular: "pinch",
    plural: "pinches",
    aliases: ["pinch", "pinches"],
  },
  dash: {
    code: "dash",
    dimension: "volume",
    system: "us",
    factor: TSP_ML / 8,
    singular: "dash",
    plural: "dashes",
    aliases: ["dash", "dashes"],
  },
  clove: countUnit("clove", "cloves", ["clove", "cloves"]),
  can: countUnit("can", "cans", ["can", "cans"]),
  slice: countUnit("slice", "slices", ["slice", "slices"]),
  bunch: countUnit("bunch", "bunches", ["bunch", "bunches"]),
  sprig: countUnit("sprig", "sprigs", ["sprig", "sprigs"]),
  stick: countUnit("stick", "sticks", ["stick", "sticks"]),
  piece: countUnit("piece", "pieces", ["piece", "pieces", "pc", "pcs"]),
  package: countUnit("package", "packages", [
    "package",
    "packages",
    "pkg",
    "pkgs",
    "packet",
    "packets",
  ]),
};

function countUnit(code: Code, plural: string, aliases: readonly string[]): UnitDef {
  return { code, dimension: "count", system: "none", factor: 1, singular: code, plural, aliases };
}

const exactAliases = new Map<string, Code>();
const looseAliases = new Map<string, Code>();
for (const def of Object.values(UNITS)) {
  for (const alias of def.aliases) looseAliases.set(alias, def.code);
  for (const alias of def.caseSensitiveAliases ?? []) exactAliases.set(alias, def.code);
}

/**
 * Resolve a unit word ("Tbsp.", "grams", "T", "fl. oz.") to its code, or null.
 * Trailing dots are ignored. "T" is tbsp and "t" is tsp (case-sensitive); every
 * other alias matches case-insensitively, so "C" and "c" are both cups.
 * Bare "oz" is weight; only "fl oz" / "fluid ounce" is volume.
 */
export function lookupUnit(word: string): Code | null {
  const cleaned = word.trim().replace(/\./g, "").replace(/\s+/g, " ");
  if (cleaned === "") return null;
  return exactAliases.get(cleaned) ?? looseAliases.get(cleaned.toLowerCase()) ?? null;
}

/**
 * Convert within a dimension. Returns null across dimensions (cups to grams
 * needs a density we do not have) and between different count units.
 */
export function convert(quantity: number, from: Code, to: Code): number | null {
  const a = UNITS[from];
  const b = UNITS[to];
  if (a.dimension !== b.dimension) return null;
  if (a.dimension === "count") return from === to ? quantity : null;
  return (quantity * a.factor) / b.factor;
}

export interface Measure {
  readonly quantity: number;
  readonly unit: Code;
}

/**
 * Express a measure in a sensible unit of `target` system.
 *
 * - Volume to metric: ml below 1 l, else l. Volume to US: tsp below 1 tbsp,
 *   tbsp below 1/4 cup, cup below 1 quart, quart below 1 gallon, else gallon.
 * - Mass to metric: g below 1 kg, else kg. Mass to US: oz below 1 lb, else lb.
 * - Count units, `pinch`, `dash` and measures already in the target system
 *   come back unchanged.
 */
export function convertForDisplay(quantity: number, unit: Code, target: TargetSystem): Measure {
  const def = UNITS[unit];
  if (def.dimension === "count" || def.system === target || unit === "pinch" || unit === "dash") {
    return { quantity, unit };
  }
  const base = quantity * def.factor;
  const to = (code: Code): Measure => ({ quantity: base / UNITS[code].factor, unit: code });
  const eps = 1e-9;
  if (def.dimension === "volume") {
    if (target === "metric") return to(base < 1000 - eps ? "ml" : "l");
    if (base < UNITS.tbsp.factor - eps) return to("tsp");
    if (base < UNITS.cup.factor / 4 - eps) return to("tbsp");
    if (base < UNITS.quart.factor - eps) return to("cup");
    if (base < UNITS.gallon.factor - eps) return to("quart");
    return to("gallon");
  }
  if (target === "metric") return to(base < 1000 - eps ? "g" : "kg");
  return to(base < UNITS.lb.factor - eps ? "oz" : "lb");
}
