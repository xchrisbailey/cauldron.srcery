import {
  copy,
  type PlanEntry,
  type Recipe,
  type RecipeInput,
  toPlanRecipe,
} from "@cauldron/shared";
import type { QueryClient, QueryKey } from "@tanstack/react-query";
import { gatherKeys } from "./gather";
import { importKeys } from "./imports";
import { planKeys } from "./plan";
import type { Notify } from "./plan-writes";
import { localToday, recipeKeys } from "./recipes";

// Every write to a recipe goes through here, and each one refreshes what it
// changed: the recipe's own query at once, then every cached query that shows
// it (the table below). It knows nothing about React: the hook in
// use-recipe-writes.ts hands it the QueryClient and the toast.

/** The recipe endpoints the writes call. `recipeApi` in recipes.ts is the real one. */
export interface RecipeApi {
  readonly create: (input: RecipeInput) => Promise<Recipe>;
  readonly update: (id: string, input: RecipeInput) => Promise<Recipe>;
  readonly banish: (id: string) => Promise<Recipe>;
  readonly restore: (id: string) => Promise<Recipe>;
  readonly duplicate: (id: string) => Promise<Recipe>;
  /** Marks the recipe cooked `on` a day, `YYYY-MM-DD`. */
  readonly cooked: (id: string, on: string) => Promise<Recipe>;
  /** Saves a distilled import's reviewed draft as a new recipe. */
  readonly saveImport: (jobId: string, input: RecipeInput) => Promise<Recipe>;
}

export interface RecipeWritesDeps {
  readonly cache: QueryClient;
  readonly api: RecipeApi;
  readonly notify: Notify;
  /** Today in the cook's calendar; `localToday` unless a test says otherwise. */
  readonly today?: () => string;
}

export type RecipeChange = "created" | "edited" | "banished" | "restored" | "cooked";

const everywhere = [
  recipeKeys.lists,
  recipeKeys.searches,
  recipeKeys.tags,
  planKeys.all,
  gatherKeys.all,
] as const;

/**
 * The cached queries that show a recipe, by what happened to it. The recipe's
 * own query is set (or dropped) by the write itself. Plan entries embed a
 * recipe's title, servings, times, photo and macros, and whether it was
 * brewed that day; the Gather list is built from planned recipes' ingredients.
 * A new recipe isn't planned yet, and cooking one changes neither its tags nor
 * its ingredients.
 */
export const shownIn: Record<RecipeChange, ReadonlyArray<QueryKey>> = {
  created: [recipeKeys.lists, recipeKeys.searches, recipeKeys.tags],
  edited: everywhere,
  banished: everywhere,
  restored: everywhere,
  cooked: [recipeKeys.lists, planKeys.all],
};

type Week = ReadonlyArray<PlanEntry>;

export function makeRecipeWrites({ cache, api, notify, today = localToday }: RecipeWritesDeps) {
  const refresh = (change: RecipeChange) => {
    for (const queryKey of shownIn[change]) void cache.invalidateQueries({ queryKey });
  };

  /** Caches what the API answered, and refreshes everything that shows it. */
  const settle = (recipe: Recipe, change: RecipeChange) => {
    cache.setQueryData(recipeKeys.detail(recipe.id), recipe);
    refresh(change);
    return recipe;
  };

  /**
   * Shows the recipe as it is now in every cached week straight away, so a
   * renamed recipe reads right before the week is refetched.
   */
  const patchWeeks = (recipe: Recipe) => {
    const planned = toPlanRecipe(recipe);
    cache.setQueriesData<Week>({ queryKey: planKeys.all }, (week) =>
      week?.some((e) => e.recipe?.id === recipe.id)
        ? week.map((e) => (e.recipe?.id === recipe.id ? { ...e, recipe: planned } : e))
        : week,
    );
  };

  // Create, update, duplicate and saveImport reject when the API refuses:
  // each page says so in its own way. The others own their toasts.

  const create = async (input: RecipeInput) => settle(await api.create(input), "created");

  const update = async (id: string, input: RecipeInput) => {
    const recipe = await api.update(id, input);
    patchWeeks(recipe);
    return settle(recipe, "edited");
  };

  /** A copy of the recipe, as a new one. */
  const duplicate = async (id: string) => settle(await api.duplicate(id), "created");

  /** Saves a distilled import as a new recipe; the job then reads as saved. */
  const saveImport = async (jobId: string, input: RecipeInput) => {
    const recipe = settle(await api.saveImport(jobId, input), "created");
    void cache.invalidateQueries({ queryKey: importKeys.detail(jobId) });
    return recipe;
  };

  /** Bring a banished recipe back. Resolves to whether it landed. */
  const restore = (id: string) =>
    api.restore(id).then(
      (recipe) => {
        settle(recipe, "restored");
        notify(copy.recipeView.restored.text);
        return true;
      },
      () => {
        notify(copy.errors.internal.text, "error");
        return false;
      },
    );

  /** Banish a recipe, with Undo in the toast. Resolves to whether it landed. */
  const banish = async (recipe: Pick<Recipe, "id" | "title">) => {
    try {
      await api.banish(recipe.id);
    } catch {
      notify(copy.errors.internal.text, "error");
      return false;
    }
    // A banished recipe reads as not found: drop it rather than keep a stale copy.
    cache.removeQueries({ queryKey: recipeKeys.detail(recipe.id) });
    refresh("banished");
    notify(copy.recipeView.banished(recipe.title).text, "info", {
      label: copy.recipeView.undo.text,
      onClick: () => void restore(recipe.id),
    });
    return true;
  };

  /** Mark a recipe cooked today. Resolves to whether it landed. */
  const brewed = async (id: string) => {
    try {
      settle(await api.cooked(id, today()), "cooked");
    } catch {
      notify(copy.brewing.couldntSave.text, "error");
      return false;
    }
    notify(copy.recipeView.brewedToday.text);
    return true;
  };

  return { create, update, banish, restore, duplicate, brewed, saveImport };
}

export type RecipeWrites = ReturnType<typeof makeRecipeWrites>;
