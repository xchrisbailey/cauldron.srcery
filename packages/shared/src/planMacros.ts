import type { PlanEntry } from "./MealPlan.ts";
import { MACRO_KEYS, type MacroKey } from "./Recipe.ts";

// Running totals for the week and each day: what the planned meals add up to,
// from each recipe's per-serving calories and macros.

/** Servings eaten for an entry: its own count, or the whole recipe when it follows the recipe. */
export const servingsOf = (entry: PlanEntry): number =>
  entry.servings ?? entry.recipe?.servings ?? 1;

export interface MacroTally {
  readonly totals: Record<MacroKey, number>;
  /** Recipe meals with every macro known. */
  readonly counted: number;
  /** Recipe meals missing some or all macros; whatever they do have is still added. */
  readonly missing: number;
  /** Free-text meals, and meals whose recipe is gone: nothing to count. */
  readonly freeText: number;
}

/** Adds up the meals' calories and macros. Unknown values add nothing and are reported. */
export const tallyMacros = (entries: ReadonlyArray<PlanEntry>): MacroTally => {
  const totals: Record<MacroKey, number> = { calories: 0, protein: 0, carbs: 0, fat: 0 };
  let counted = 0;
  let missing = 0;
  let freeText = 0;
  for (const entry of entries) {
    if (entry.recipe === null) {
      freeText++;
      continue;
    }
    const servings = servingsOf(entry);
    let known = 0;
    for (const key of MACRO_KEYS) {
      const value = entry.recipe.macros[key];
      if (value === null) continue;
      totals[key] += value * servings;
      known++;
    }
    if (known === MACRO_KEYS.length) counted++;
    else missing++;
  }
  return { totals, counted, missing, freeText };
};

/** Whether any meal added anything. */
export const hasMacros = (tally: MacroTally) =>
  tally.totals.calories + tally.totals.protein + tally.totals.carbs + tally.totals.fat > 0;

/**
 * Days and servings for spreading one recipe over the week: one serving a day
 * from `from`, until the recipe's servings run out or the week ends.
 */
export const oneADay = (
  days: ReadonlyArray<string>,
  from: string,
  servings: number | null,
): Map<string, number> => {
  const start = Math.max(0, days.indexOf(from));
  const count = Math.min(servings ?? 1, days.length - start);
  return new Map(days.slice(start, start + count).map((day) => [day, 1]));
};
