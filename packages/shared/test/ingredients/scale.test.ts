import { describe, expect, it } from "vite-plus/test";
import {
  formatMeasure,
  formatQuantity,
  parseIngredientLine,
  scaleQuantity,
} from "../../src/index.ts";

describe("scaleQuantity", () => {
  it("scales single values and ranges", () => {
    expect(scaleQuantity({ min: 1.5, max: null }, 2)).toEqual({ min: 3, max: null });
    expect(scaleQuantity({ min: 2, max: 3 }, 0.5)).toEqual({ min: 1, max: 1.5 });
  });
});

describe("formatQuantity, US and counts use fractions", () => {
  it.each([
    [1.5, "cup", "1 ½"],
    [0.5, "cup", "½"],
    [0.75, "tsp", "¾"],
    [1 / 3, "cup", "⅓"],
    [2 / 3, "cup", "⅔"],
    [0.3333, "cup", "⅓"],
    [0.25, "tbsp", "¼"],
    [0.125, "tsp", "⅛"],
    [2, "cup", "2"],
    [2.97, "cup", "3"],
    [2.98, "cup", "3"],
    [3.6, "cup", "3 ⅝"],
    [0.01, "tsp", "⅛"],
    [0, "tsp", "0"],
    [10.5, "oz", "10 ½"],
    [1.49, "cup", "1 ½"],
    [1.9, "cup", "1 ⅞"],
    [3, null, "3"],
    [0.5, null, "½"],
    [2, "clove", "2"],
    [1.25, "lb", "1 ¼"],
  ] as const)("%d %s is %s", (value, unit, expected) => {
    expect(formatQuantity({ min: value, max: null }, unit)).toBe(expected);
  });

  it("formats ranges with an en dash", () => {
    expect(formatQuantity({ min: 2, max: 3 }, "clove")).toBe("2–3");
    expect(formatQuantity({ min: 0.5, max: 1.5 }, "cup")).toBe("½–1 ½");
  });

  it("collapses a range that rounds to one value", () => {
    expect(formatQuantity({ min: 2, max: 2.01 }, "cup")).toBe("2");
  });
});

describe("formatQuantity, metric uses decimals", () => {
  it.each([
    [250, "g", "250"],
    [1.5, "kg", "1.5"],
    [1.25, "kg", "1.25"],
    [236.588, "ml", "237"],
    [12.5, "g", "12.5"],
    [12.04, "g", "12"],
    [0.5, "l", "0.5"],
    [4.929, "ml", "4.93"],
    [2, "kg", "2"],
    [0.001, "g", "0.001"],
  ] as const)("%d %s is %s", (value, unit, expected) => {
    expect(formatQuantity({ min: value, max: null }, unit)).toBe(expected);
  });

  it("formats metric ranges", () => {
    expect(formatQuantity({ min: 350, max: 400 }, "g")).toBe("350–400");
  });
});

describe("formatMeasure", () => {
  it("adds a unit label", () => {
    expect(formatMeasure({ min: 1.5, max: null }, "cup")).toBe("1 ½ c");
    expect(formatMeasure({ min: 250, max: null }, "g")).toBe("250 g");
    expect(formatMeasure({ min: 2, max: 3 }, "clove")).toBe("2–3 cloves");
    expect(formatMeasure({ min: 1, max: null }, "clove")).toBe("1 clove");
    expect(formatMeasure({ min: 2, max: null }, null)).toBe("2");
  });
});

describe("parse, scale, format", () => {
  it("doubles a parsed line", () => {
    const p = parseIngredientLine("1 1/2 cups flour");
    expect(formatQuantity(scaleQuantity(p.quantity!, 2), p.unit)).toBe("3");
    expect(formatQuantity(scaleQuantity(p.quantity!, 1 / 3), p.unit)).toBe("½");
  });
});
