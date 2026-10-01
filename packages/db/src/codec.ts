import {
  ingredientKey,
  MAX_QUANTITY,
  type Ingredient,
  type IngredientInput,
  type Macros,
  type MacrosInput,
  type Quantity,
  type UnitCode,
} from "@cauldron/shared";

// The one mapping between domain shapes and their columns. Everything that
// reads or writes quantities, ingredient lines or macros goes through here, so
// rounding and blank-to-null happen the same way everywhere.

/** Blank optional text is stored as null. */
const orNull = (value: string | null): string | null =>
  value === null || value === "" ? null : value;

interface QuantityRow {
  readonly quantityMin: number | null;
  readonly quantityMax: number | null;
}

/**
 * Rounds to the quantity columns' scale (numeric(12, 4)) and caps at their
 * maximum, so a value compared before a write matches the one read back.
 */
const round = (n: number) => Math.min(MAX_QUANTITY, Math.round(n * 10_000) / 10_000);

export const quantity = {
  round,
  toRow: (q: Quantity | null): QuantityRow =>
    q === null
      ? { quantityMin: null, quantityMax: null }
      : { quantityMin: round(q.min), quantityMax: q.max === null ? null : round(q.max) },
  fromRow: (row: QuantityRow): Quantity | null =>
    row.quantityMin === null ? null : { min: row.quantityMin, max: row.quantityMax ?? null },
};

/** The `recipe_ingredient` columns a line maps to; the caller adds owner, recipe and position. */
export interface IngredientRow {
  readonly section: string | null;
  readonly quantityMin: number | null;
  readonly quantityMax: number | null;
  readonly unit: UnitCode | null;
  readonly item: string;
  readonly itemKey: string;
  readonly note: string | null;
  readonly optional: boolean;
  readonly altQuantityMin: number | null;
  readonly altQuantityMax: number | null;
  readonly altUnit: UnitCode | null;
  readonly originalLine: string;
}

export const ingredient = {
  toRow: (line: IngredientInput): IngredientRow => {
    const alt = quantity.toRow(line.alt?.quantity ?? null);
    return {
      section: orNull(line.section),
      ...quantity.toRow(line.quantity),
      unit: line.unit,
      item: line.item,
      itemKey: ingredientKey(line.item),
      note: orNull(line.note),
      optional: line.optional,
      altQuantityMin: alt.quantityMin,
      altQuantityMax: alt.quantityMax,
      altUnit: line.alt?.unit ?? null,
      originalLine: line.original,
    };
  },
  fromRow: (row: IngredientRow): Ingredient => {
    const altQuantity = quantity.fromRow({
      quantityMin: row.altQuantityMin,
      quantityMax: row.altQuantityMax,
    });
    return {
      section: row.section,
      quantity: quantity.fromRow(row),
      unit: row.unit,
      item: row.item,
      note: row.note,
      optional: row.optional,
      // A second measure needs both an amount and a unit.
      alt:
        altQuantity === null || row.altUnit === null
          ? null
          : { quantity: altQuantity, unit: row.altUnit },
      original: row.originalLine,
      itemKey: row.itemKey,
    };
  },
};

/** The per-serving macro columns on `recipe`. */
export interface MacrosRow {
  readonly calories: number | null;
  readonly proteinGrams: number | null;
  readonly carbsGrams: number | null;
  readonly fatGrams: number | null;
}

export const macros = {
  toRow: (m: MacrosInput): MacrosRow => ({
    calories: m.calories,
    proteinGrams: m.protein,
    carbsGrams: m.carbs,
    fatGrams: m.fat,
  }),
  fromRow: (row: MacrosRow): Macros => ({
    calories: row.calories,
    protein: row.proteinGrams,
    carbs: row.carbsGrams,
    fat: row.fatGrams,
  }),
};
