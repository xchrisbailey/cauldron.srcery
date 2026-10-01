import type {
  MacroEstimateInput,
  Recipe,
  RecipeId,
  RecipeInput,
  RecipeSort,
  TagId,
} from "@cauldron/shared";
import { infiniteQueryOptions, queryOptions, type QueryClient } from "@tanstack/react-query";
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

export interface LibraryFilters {
  readonly q: string;
  readonly tag: string | undefined;
  readonly sort: RecipeSort;
}

const PAGE = 30;

/** The library, a page at a time on the API's cursor. */
export const libraryQuery = (filters: LibraryFilters) =>
  infiniteQueryOptions({
    queryKey: ["recipes", "list", filters] as const,
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      callApi((c) =>
        c.recipes.list({
          query: {
            limit: PAGE,
            sort: filters.sort,
            ...(pageParam === undefined ? {} : { cursor: pageParam }),
            ...(filters.q.trim() === "" ? {} : { q: filters.q.trim() }),
            ...(filters.tag === undefined ? {} : { tag: filters.tag as TagId }),
          },
        }),
      ),
    getNextPageParam: (page) => page.nextCursor ?? undefined,
  });

/** Best matches for the ⌘K palette. */
export const summonQuery = (q: string) =>
  queryOptions({
    queryKey: ["recipes", "search", q] as const,
    queryFn: () => callApi((c) => c.recipes.search({ query: { q, limit: 8 } })),
    enabled: q.trim() !== "",
    staleTime: 30_000,
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

/** The model's per-serving estimate from ingredient lines. Nothing is saved. */
export const estimateMacros = (input: MacroEstimateInput) =>
  callApi((c) => c.recipes.estimateMacros({ payload: input }));

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
