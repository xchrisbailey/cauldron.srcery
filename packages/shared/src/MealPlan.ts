import { Schema } from "effect";
import { validation } from "./copy.ts";
import { LocalDate, RECIPE_LIMITS, RecipeId } from "./Recipe.ts";

// The week (#18): what's planned for each day's meals. An entry is a recipe
// (with its own servings) or a free-text meal like "Leftovers".

export const PlanEntryId = Schema.String.check(Schema.isUUID()).pipe(Schema.brand("PlanEntryId"));
export type PlanEntryId = typeof PlanEntryId.Type;

export const MEAL_SLOTS = ["breakfast", "lunch", "dinner", "snack"] as const;
export const MealSlot = Schema.Literals(MEAL_SLOTS);
export type MealSlot = typeof MealSlot.Type;

export const PLAN_LIMITS = {
  title: RECIPE_LIMITS.title,
  servings: RECIPE_LIMITS.servings,
  /** Entries in one meal slot on one day. */
  perSlot: 20,
  /** The longest range one read or clear may cover. */
  rangeDays: 62,
} as const;

const Title = Schema.Trim.check(
  Schema.isNonEmpty({ message: validation.required.text }),
  Schema.isMaxLength(PLAN_LIMITS.title, { message: validation.tooLong(PLAN_LIMITS.title).text }),
);

const Servings = Schema.Int.annotate({
  message: validation.wholeNumber(1, PLAN_LIMITS.servings).text,
}).check(
  Schema.isBetween(
    { minimum: 1, maximum: PLAN_LIMITS.servings },
    { message: validation.wholeNumber(1, PLAN_LIMITS.servings).text },
  ),
);

/** The recipe behind an entry, while it's live. */
export const PlanRecipe = Schema.Struct({
  id: RecipeId,
  title: Schema.String,
  servings: Schema.NullOr(Schema.Int),
  /** Total time, or prep plus cook when the total isn't set. */
  totalMinutes: Schema.NullOr(Schema.Int),
  photoKey: Schema.NullOr(Schema.String),
}).annotate({ identifier: "PlanRecipe" });
export type PlanRecipe = typeof PlanRecipe.Type;

// Plain structs rather than classes, so the web app can copy and edit entries
// for optimistic updates.
export const PlanEntry = Schema.Struct({
  id: PlanEntryId,
  date: LocalDate,
  slot: MealSlot,
  /**
   * What the entry says: the free text, or the recipe's title when it was
   * stirred in. Shown when the recipe has since been banished.
   */
  title: Schema.String,
  /** Null for free text, and while the recipe is banished. */
  recipe: Schema.NullOr(PlanRecipe),
  /** Servings to cook; null means the recipe's own. */
  servings: Schema.NullOr(Schema.Int),
  /** Order within the day's slot, from 0. */
  position: Schema.Int,
  /** The recipe was marked cooked on this entry's day. */
  brewed: Schema.Boolean,
}).annotate({ identifier: "PlanEntry" });
export type PlanEntry = typeof PlanEntry.Type;

/** A day range, both ends included. */
export const PlanRangeQuery = Schema.Struct({ from: LocalDate, to: LocalDate });
export type PlanRangeQuery = typeof PlanRangeQuery.Type;

/** Stir a recipe in (with `recipeId`), or add a free-text meal (with `title`). */
export const PlanEntryInput = Schema.Struct({
  date: LocalDate,
  slot: MealSlot,
  recipeId: Schema.optionalKey(Schema.NullOr(RecipeId)),
  title: Schema.optionalKey(Schema.NullOr(Title)),
  servings: Schema.optionalKey(Schema.NullOr(Servings)),
  /** Where in the slot; the end when left out. */
  position: Schema.optionalKey(Schema.Int.check(Schema.isGreaterThanOrEqualTo(0))),
});
export type PlanEntryInput = typeof PlanEntryInput.Type;

/** Move an entry (date, slot, position), change its servings, or rename free text. */
export const PlanEntryUpdate = Schema.Struct({
  date: Schema.optionalKey(LocalDate),
  slot: Schema.optionalKey(MealSlot),
  position: Schema.optionalKey(Schema.Int.check(Schema.isGreaterThanOrEqualTo(0))),
  servings: Schema.optionalKey(Schema.NullOr(Servings)),
  title: Schema.optionalKey(Title),
});
export type PlanEntryUpdate = typeof PlanEntryUpdate.Type;

/** Copy every entry from the seven days starting `from` into the seven days starting `to`. */
export const PlanCopyInput = Schema.Struct({ from: LocalDate, to: LocalDate });
export type PlanCopyInput = typeof PlanCopyInput.Type;
