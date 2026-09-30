import { Schema } from "effect";
import { UNIT_CODES } from "./units.ts";

/** A quantity: a single amount (`max` null) or a range from `min` to `max`. */
export const Quantity = Schema.Struct({
  min: Schema.Finite.check(Schema.isGreaterThanOrEqualTo(0)),
  max: Schema.NullOr(Schema.Finite.check(Schema.isGreaterThanOrEqualTo(0))),
});
export type Quantity = typeof Quantity.Type;

/** Normalized unit code, see `UNITS` in `units.ts`. */
export const UnitCode = Schema.Literals(UNIT_CODES);
export type UnitCode = typeof UnitCode.Type;

/** A second measure for the same ingredient, e.g. the "(190g)" in "1 1/2 cups (190g) flour". */
export const AltMeasure = Schema.Struct({
  quantity: Quantity,
  unit: UnitCode,
});
export type AltMeasure = typeof AltMeasure.Type;

export const ParsedIngredient = Schema.Struct({
  quantity: Schema.NullOr(Quantity),
  unit: Schema.NullOr(UnitCode),
  item: Schema.String,
  note: Schema.NullOr(Schema.String),
  optional: Schema.Boolean,
  alt: Schema.NullOr(AltMeasure),
  original: Schema.String,
});
export type ParsedIngredient = typeof ParsedIngredient.Type;
