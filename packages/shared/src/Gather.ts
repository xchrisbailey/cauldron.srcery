import { Schema } from "effect";
import { validation } from "./copy.ts";
import { Aisle } from "./gather/aisles.ts";
import { Quantity, UnitCode } from "./ingredients/schema.ts";
import { LocalDate, RECIPE_LIMITS, RecipeId } from "./Recipe.ts";

// The Gather list (#19): a week's shopping list, built from the planned
// recipes and kept in step with the week, plus items added by hand.

export const GatherItemId = Schema.String.check(Schema.isUUID()).pipe(Schema.brand("GatherItemId"));
export type GatherItemId = typeof GatherItemId.Type;

/** One recipe that needs this item, and how much of it. */
export const GatherSource = Schema.Struct({
  recipeId: RecipeId,
  title: Schema.String,
  quantity: Schema.NullOr(Quantity),
  unit: Schema.NullOr(UnitCode),
});
export type GatherSource = typeof GatherSource.Type;

export const GatherItem = Schema.Struct({
  id: GatherItemId,
  item: Schema.String,
  itemKey: Schema.String,
  quantity: Schema.NullOr(Quantity),
  unit: Schema.NullOr(UnitCode),
  aisle: Aisle,
  checked: Schema.Boolean,
  /** Added by hand rather than gathered from the week. */
  manual: Schema.Boolean,
  /** Marked as already in the pantry; remembered for this item in every week. */
  inPantry: Schema.Boolean,
  sources: Schema.Array(GatherSource),
}).annotate({ identifier: "GatherItem" });
export type GatherItem = typeof GatherItem.Type;

export const GatherList = Schema.Struct({
  /** The first day of the week; the list covers it and the six days after. */
  weekStart: LocalDate,
  /** Planned recipes the list was gathered from. */
  recipeCount: Schema.Int,
  /** In store order: by aisle, then by item. */
  items: Schema.Array(GatherItem),
}).annotate({ identifier: "GatherList" });
export type GatherList = typeof GatherList.Type;

/** Add an item by hand, written like an ingredient line: "2 lemons", "oat milk". */
export const GatherItemInput = Schema.Struct({
  line: Schema.Trim.check(
    Schema.isNonEmpty({ message: validation.required.text }),
    Schema.isMaxLength(RECIPE_LIMITS.line, {
      message: validation.tooLong(RECIPE_LIMITS.line).text,
    }),
  ),
});
export type GatherItemInput = typeof GatherItemInput.Type;

export const GatherItemUpdate = Schema.Struct({
  checked: Schema.optionalKey(Schema.Boolean),
  inPantry: Schema.optionalKey(Schema.Boolean),
});
export type GatherItemUpdate = typeof GatherItemUpdate.Type;
