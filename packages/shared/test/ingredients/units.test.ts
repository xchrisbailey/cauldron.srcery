import { Schema } from "effect";
import { describe, expect, it } from "vite-plus/test";
import {
  Quantity,
  ParsedIngredient,
  UNIT_CODES,
  UNITS,
  UnitCode,
  convert,
  convertForDisplay,
  lookupUnit,
  parseIngredientLine,
} from "../../src/index.ts";

describe("catalog", () => {
  it("has a definition for every code, with unique aliases", () => {
    const seen = new Map<string, string>();
    for (const code of UNIT_CODES) {
      const def = UNITS[code];
      expect(def.code).toBe(code);
      for (const alias of [...def.aliases, ...(def.caseSensitiveAliases ?? [])]) {
        expect(seen.get(alias), `${alias} on ${code}`).toBeUndefined();
        seen.set(alias, code);
      }
    }
  });

  it.each([
    ["T", "tbsp"],
    ["t", "tsp"],
    ["Tbsp.", "tbsp"],
    ["tablespoons", "tbsp"],
    ["TSP", "tsp"],
    ["c.", "cup"],
    ["C", "cup"],
    ["lbs", "lb"],
    ["grams", "g"],
    ["Fl. Oz.", "fl_oz"],
    ["fluid ounces", "fl_oz"],
    ["oz", "oz"],
    ["cloves", "clove"],
  ])("lookupUnit(%j) is %s", (word, code) => {
    expect(lookupUnit(word)).toBe(code);
  });

  it.each(["", "flour", "large", "x"])("lookupUnit(%j) is not a unit", (word) => {
    expect(lookupUnit(word)).toBeNull();
  });
});

describe("convert", () => {
  it("converts volume", () => {
    expect(convert(1, "cup", "ml")).toBeCloseTo(236.588, 2);
    expect(convert(3, "tsp", "tbsp")).toBeCloseTo(1, 10);
    expect(convert(16, "tbsp", "cup")).toBeCloseTo(1, 10);
    expect(convert(4, "cup", "quart")).toBeCloseTo(1, 10);
    expect(convert(1, "gallon", "l")).toBeCloseTo(3.785, 3);
    expect(convert(8, "fl_oz", "cup")).toBeCloseTo(1, 10);
    expect(convert(2, "pint", "quart")).toBeCloseTo(1, 10);
    expect(convert(1, "l", "ml")).toBe(1000);
  });

  it("converts mass", () => {
    expect(convert(1, "lb", "g")).toBeCloseTo(453.592, 2);
    expect(convert(16, "oz", "lb")).toBeCloseTo(1, 10);
    expect(convert(1.5, "kg", "g")).toBe(1500);
  });

  it("returns null across dimensions and between different counts", () => {
    expect(convert(1, "cup", "g")).toBeNull();
    expect(convert(1, "oz", "fl_oz")).toBeNull();
    expect(convert(1, "clove", "piece")).toBeNull();
    expect(convert(3, "clove", "clove")).toBe(3);
  });

  it("round trips", () => {
    for (const a of UNIT_CODES) {
      for (const b of UNIT_CODES) {
        const there = convert(7, a, b);
        if (there !== null) expect(convert(there, b, a)).toBeCloseTo(7, 8);
      }
    }
  });
});

describe("convertForDisplay", () => {
  it.each([
    [1, "cup", "metric", 236.588, "ml"],
    [4.5, "cup", "metric", 1.0647, "l"],
    [1, "tsp", "metric", 4.929, "ml"],
    [2, "lb", "metric", 907.185, "g"],
    [5, "lb", "metric", 2.268, "kg"],
    [8, "oz", "metric", 226.796, "g"],
    [250, "ml", "us", 1.0567, "cup"],
    [5, "ml", "us", 1.0144, "tsp"],
    [20, "ml", "us", 1.352, "tbsp"],
    [1000, "ml", "us", 1.0567, "quart"],
    [4, "l", "us", 1.0567, "gallon"],
    [100, "g", "us", 3.527, "oz"],
    [1, "kg", "us", 2.2046, "lb"],
  ] as const)("%d %s to %s", (q, from, system, expected, unit) => {
    const out = convertForDisplay(q, from, system);
    expect(out.unit).toBe(unit);
    expect(out.quantity).toBeCloseTo(expected, 2);
  });

  it("steps small US volumes down within the US system", () => {
    expect(convertForDisplay(0.125, "cup", "us")).toEqual({ quantity: 2, unit: "tbsp" });
    expect(convertForDisplay(1 / 32, "cup", "us").unit).toBe("tsp");
    expect(convertForDisplay(0.5, "tbsp", "us")).toEqual({ quantity: 1.5, unit: "tsp" });
    expect(convertForDisplay(0.25, "cup", "us")).toEqual({ quantity: 0.25, unit: "cup" });
    expect(convertForDisplay(1, "tbsp", "us")).toEqual({ quantity: 1, unit: "tbsp" });
  });

  it("leaves matching systems, counts, pinch and dash alone", () => {
    expect(convertForDisplay(2, "cup", "us")).toEqual({ quantity: 2, unit: "cup" });
    expect(convertForDisplay(2, "g", "metric")).toEqual({ quantity: 2, unit: "g" });
    expect(convertForDisplay(3, "clove", "metric")).toEqual({ quantity: 3, unit: "clove" });
    expect(convertForDisplay(1, "pinch", "metric")).toEqual({ quantity: 1, unit: "pinch" });
    expect(convertForDisplay(1, "dash", "metric")).toEqual({ quantity: 1, unit: "dash" });
  });
});

describe("schemas", () => {
  it("accepts every unit code and rejects others", () => {
    for (const code of UNIT_CODES) expect(Schema.is(UnitCode)(code)).toBe(true);
    expect(Schema.is(UnitCode)("furlong")).toBe(false);
  });

  it("Quantity enforces max >= min", () => {
    const ok = Schema.is(Quantity);
    expect(ok({ min: 1, max: null })).toBe(true);
    expect(ok({ min: 1, max: 1 })).toBe(true);
    expect(ok({ min: 1, max: 2 })).toBe(true);
    expect(ok({ min: 3, max: 2 })).toBe(false);
    expect(ok({ min: -1, max: null })).toBe(false);
  });

  it("accepts parser output", () => {
    const parsed = parseIngredientLine("1 1/2 cups (190g) flour, sifted");
    expect(Schema.is(ParsedIngredient)(parsed)).toBe(true);
    expect(Schema.decodeUnknownSync(ParsedIngredient)(parsed)).toEqual(parsed);
  });

  it("rejects negative and non-finite quantities", () => {
    const bad = { ...parseIngredientLine("1 cup milk"), quantity: { min: -1, max: null } };
    expect(Schema.is(ParsedIngredient)(bad)).toBe(false);
    const inf = { ...parseIngredientLine("1 cup milk"), quantity: { min: Infinity, max: null } };
    expect(Schema.is(ParsedIngredient)(inf)).toBe(false);
  });
});
