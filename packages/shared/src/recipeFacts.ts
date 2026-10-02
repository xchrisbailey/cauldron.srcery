import { library } from "./copy.ts";
import type { PlanRecipe } from "./MealPlan.ts";
import { type Macros, RECIPE_LIMITS, type RecipeSummary } from "./Recipe.ts";

// Facts every client works out the same way from a recipe: how long it takes,
// how much to scale it by, and the slice of it the week shows.

type Times = Pick<RecipeSummary, "totalMinutes" | "prepMinutes" | "cookMinutes">;

/** Total time, or prep plus cook when the total isn't set. */
export const recipeMinutes = (recipe: Times): number | null =>
  recipe.totalMinutes ??
  (recipe.prepMinutes !== null || recipe.cookMinutes !== null
    ? (recipe.prepMinutes ?? 0) + (recipe.cookMinutes ?? 0)
    : null);

/**
 * How much to scale quantities by to cook `wanted` servings of a recipe that
 * makes `recipeServings`. Unchanged when either is unknown.
 */
export const servingFactor = (recipeServings: number | null, wanted: number | null): number =>
  recipeServings !== null && wanted !== null ? wanted / recipeServings : 1;

/** A recipe as the week shows it. */
export const toPlanRecipe = (
  recipe: Times & Pick<RecipeSummary, "id" | "title" | "servings" | "photoKey" | "macros">,
): PlanRecipe => ({
  id: recipe.id,
  title: recipe.title,
  servings: recipe.servings,
  totalMinutes: recipeMinutes(recipe),
  photoKey: recipe.photoKey,
  macros: recipe.macros,
});

/** In the order a card reads them: calories, then protein, fat and carbs. */
const MACRO_LINE_ORDER = ["calories", "protein", "fat", "carbs"] as const;

/**
 * A recipe's per-serving macros as one compact line ("420 kcal · 32P · 18F ·
 * 30C") and the words a screen reader says for it. Unknown values are left
 * out; null when none are known.
 */
export const macroLine = (macros: Macros): { text: string; label: string } | null => {
  const known = MACRO_LINE_ORDER.flatMap((key) => {
    const value = macros[key];
    return value === null ? [] : [{ key, value: Math.round(value).toLocaleString("en") }];
  });
  if (known.length === 0) return null;
  const { macroLine: copy } = library;
  return {
    text: known.map(({ key, value }) => copy[key](value).text).join(" · "),
    label: copy.spoken.label(known.map(({ key, value }) => copy.spoken[key](value).text).join(", "))
      .text,
  };
};

// ---------------------------------------------------------------------------
// Scaling a recipe while reading or brewing it: by servings when the recipe
// has them, otherwise by a multiplier from a fixed ladder. The recipe page
// steps it, hands it to brew in the URL, and brew reads it back.

export const SCALE_MULTIPLIERS = [0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 8] as const;

export type Scale =
  | { readonly by: "servings"; readonly servings: number }
  | { readonly by: "multiplier"; readonly multiplier: number };

/** A scale as it travels in a URL. */
export type ScaleSearch = { readonly servings?: number; readonly multiplier?: number };

const unscaled: Scale = { by: "multiplier", multiplier: 1 };

const isServings = (n: number) => Number.isInteger(n) && n >= 1 && n <= RECIPE_LIMITS.servings;
const isMultiplier = (n: number) => (SCALE_MULTIPLIERS as ReadonlyArray<number>).includes(n);

const next = (scale: Scale, direction: 1 | -1): Scale | null => {
  if (scale.by === "servings") {
    const servings = scale.servings + direction;
    return isServings(servings) ? { by: "servings", servings } : null;
  }
  const ladder = direction === 1 ? SCALE_MULTIPLIERS : [...SCALE_MULTIPLIERS].reverse();
  const multiplier = ladder.find((m) =>
    direction === 1 ? m > scale.multiplier : m < scale.multiplier,
  );
  return multiplier === undefined ? null : { by: "multiplier", multiplier };
};

const asNumber = (value: unknown) =>
  typeof value === "number" || (typeof value === "string" && value.trim() !== "")
    ? Number(value)
    : Number.NaN;

export const Scale = {
  /** The recipe as written: its own servings, or a multiplier of 1. */
  initialScale: (recipe: { readonly servings: number | null }): Scale =>
    recipe.servings !== null ? { by: "servings", servings: recipe.servings } : unscaled,

  /** The factor a scale applies to the quantities of a recipe that makes `recipeServings`. */
  factor: (scale: Scale, recipeServings: number | null): number =>
    scale.by === "servings" ? servingFactor(recipeServings, scale.servings) : scale.multiplier,

  /** Whether there's a serving, or a rung of the ladder, further that way. */
  canStep: (scale: Scale, direction: 1 | -1): boolean => next(scale, direction) !== null,

  /** One serving, or one rung of the ladder, more or fewer; the same scale at either end. */
  step: (scale: Scale, direction: 1 | -1): Scale => next(scale, direction) ?? scale,

  /** The search params for a scale; none when it's a multiplier of 1. */
  toSearch: (scale: Scale): ScaleSearch =>
    scale.by === "servings"
      ? { servings: scale.servings }
      : scale.multiplier !== 1
        ? { multiplier: scale.multiplier }
        : {},

  /**
   * The scale in search params, held to the bounds `step` keeps: whole
   * servings up to the recipe limit, or a multiplier on the ladder. Anything
   * else reads as unscaled.
   */
  fromSearch: (search: { readonly servings?: unknown; readonly multiplier?: unknown }): Scale => {
    const servings = asNumber(search.servings);
    if (isServings(servings)) return { by: "servings", servings };
    const multiplier = asNumber(search.multiplier);
    return isMultiplier(multiplier) ? { by: "multiplier", multiplier } : unscaled;
  },
};
