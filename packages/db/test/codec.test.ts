import type { IngredientInput } from "@cauldron/shared";
import { describe, expect, it } from "vite-plus/test";
import { ingredient, macros, quantity } from "../src/index.ts";

const line = (overrides: Partial<IngredientInput> = {}): IngredientInput => ({
  section: null,
  quantity: { min: 2, max: null },
  unit: "cup",
  item: "flour",
  note: null,
  optional: false,
  alt: null,
  original: "2 cups flour",
  ...overrides,
});

describe("quantity", () => {
  it("rounds to the column's four places", () => {
    const row = quantity.toRow({ min: 1 / 3, max: 2 / 3 });
    expect(row).toEqual({ quantityMin: 0.3333, quantityMax: 0.6667 });
    expect(quantity.fromRow(row)).toEqual({ min: 0.3333, max: 0.6667 });
    expect(quantity.round(1 / 3)).toBe(0.3333);
  });

  it("caps at the column's maximum", () => {
    expect(quantity.round(1e12)).toBe(99_999_999);
  });

  it("keeps a single amount's max null", () => {
    const row = quantity.toRow({ min: 2, max: null });
    expect(row).toEqual({ quantityMin: 2, quantityMax: null });
    expect(quantity.fromRow(row)).toEqual({ min: 2, max: null });
  });

  it("maps no quantity to null columns and back", () => {
    expect(quantity.toRow(null)).toEqual({ quantityMin: null, quantityMax: null });
    expect(quantity.fromRow({ quantityMin: null, quantityMax: null })).toBeNull();
  });
});

describe("ingredient", () => {
  it("round-trips a line, rounding 1/3 to 0.3333", () => {
    const input = line({
      section: "For the sauce",
      quantity: { min: 1 / 3, max: null },
      note: "sifted",
      alt: { quantity: { min: 40, max: 45 }, unit: "g" },
      original: "1/3 cup (40-45g) flour, sifted",
    });
    const row = ingredient.toRow(input);
    expect(row).toMatchObject({
      quantityMin: 0.3333,
      quantityMax: null,
      itemKey: "flour",
      altQuantityMin: 40,
      altQuantityMax: 45,
      altUnit: "g",
      originalLine: "1/3 cup (40-45g) flour, sifted",
    });
    expect(ingredient.fromRow(row)).toEqual({
      ...input,
      quantity: { min: 0.3333, max: null },
      itemKey: "flour",
    });
  });

  it("round-trips a range with a null max", () => {
    const row = ingredient.toRow(line({ quantity: { min: 2, max: null } }));
    expect(row.quantityMax).toBeNull();
    expect(ingredient.fromRow(row).quantity).toEqual({ min: 2, max: null });
  });

  it("reads an alt amount without a unit as no alt", () => {
    const row = { ...ingredient.toRow(line()), altQuantityMin: 190, altUnit: null };
    expect(ingredient.fromRow(row).alt).toBeNull();
  });

  it("writes no alt as null columns", () => {
    const row = ingredient.toRow(line({ alt: null }));
    expect(row).toMatchObject({ altQuantityMin: null, altQuantityMax: null, altUnit: null });
    expect(ingredient.fromRow(row).alt).toBeNull();
  });

  it("stores a blank note and section as null", () => {
    const row = ingredient.toRow(line({ note: "", section: "" }));
    expect(row.note).toBeNull();
    expect(row.section).toBeNull();
    expect(ingredient.fromRow(row)).toMatchObject({ note: null, section: null });
  });
});

describe("macros", () => {
  it("round-trips, unknowns included", () => {
    const value = { calories: 310, protein: 17.5, carbs: null, fat: 19 };
    const row = macros.toRow(value);
    expect(row).toEqual({ calories: 310, proteinGrams: 17.5, carbsGrams: null, fatGrams: 19 });
    expect(macros.fromRow(row)).toEqual(value);
  });
});
