import type { Recipe, RecipeId, RecipeInput } from "@cauldron/shared";
import { queryOptions, type QueryClient } from "@tanstack/react-query";
import { callApi } from "./api";

// Recipe queries and writes for TanStack Query. Keys start with "recipes" so
// one invalidation refreshes the library, search and every open recipe.

export const recipeKeys = {
  all: ["recipes"] as const,
  detail: (id: string) => ["recipes", "detail", id] as const,
  tags: ["tags"] as const,
};

export const recipeQuery = (id: string) =>
  queryOptions({
    queryKey: recipeKeys.detail(id),
    queryFn: () => callApi((c) => c.recipes.get({ params: { id: id as RecipeId } })),
  });

export const tagsQuery = () =>
  queryOptions({
    queryKey: recipeKeys.tags,
    queryFn: () => callApi((c) => c.tags.list()),
    staleTime: 60_000,
  });

export const createRecipe = (input: RecipeInput) =>
  callApi((c) => c.recipes.create({ payload: input }));

export const updateRecipe = (id: string, input: RecipeInput) =>
  callApi((c) => c.recipes.update({ params: { id: id as RecipeId }, payload: input }));

const asId = (id: string) => ({ params: { id: id as RecipeId } });

export const banishRecipe = (id: string) => callApi((c) => c.recipes.banish(asId(id)));
export const restoreRecipe = (id: string) => callApi((c) => c.recipes.restore(asId(id)));
export const duplicateRecipe = (id: string) => callApi((c) => c.recipes.duplicate(asId(id)));
export const markCooked = (id: string, on: string) =>
  callApi((c) => c.recipes.cooked({ ...asId(id), payload: { on } }));

/** Today in the cook's own calendar, `YYYY-MM-DD`. */
export const localToday = (now = new Date()) =>
  `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

/** After a write: cache the recipe and refresh lists and tags. */
export const settleRecipe = (queryClient: QueryClient, recipe: Recipe) => {
  queryClient.setQueryData(recipeKeys.detail(recipe.id), recipe);
  void queryClient.invalidateQueries({
    queryKey: recipeKeys.all,
    predicate: (query) => query.queryKey[1] !== "detail",
  });
  void queryClient.invalidateQueries({ queryKey: recipeKeys.tags });
};
