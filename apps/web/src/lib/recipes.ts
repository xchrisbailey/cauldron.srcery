import type { MacroEstimateInput, RecipeId, RecipeSort, TagId } from "@cauldron/shared";
import { infiniteQueryOptions, queryOptions } from "@tanstack/react-query";
import { callApi } from "./api";
import { saveImport } from "./imports";
import type { RecipeApi } from "./recipe-writes";

// Recipe queries for TanStack Query, and the endpoints the writes in
// recipe-writes.ts call. Every write refreshes the queries that show what it
// changed; recipe-writes.ts keeps the table.

export const recipeKeys = {
  detail: (id: string) => ["recipes", "detail", id] as const,
  /** Every page of the library, whatever its filters. */
  lists: ["recipes", "list"] as const,
  list: (filters: LibraryFilters) => ["recipes", "list", filters] as const,
  /** Every ⌘K search. */
  searches: ["recipes", "search"] as const,
  search: (q: string) => ["recipes", "search", q] as const,
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
    queryKey: recipeKeys.list(filters),
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
    queryKey: recipeKeys.search(q),
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

const asId = (id: string) => ({ params: { id: id as RecipeId } });

/** The recipe endpoints, for the writes in recipe-writes.ts. */
export const recipeApi: RecipeApi = {
  create: (input) => callApi((c) => c.recipes.create({ payload: input })),
  update: (id, input) => callApi((c) => c.recipes.update({ ...asId(id), payload: input })),
  banish: (id) => callApi((c) => c.recipes.banish(asId(id))),
  restore: (id) => callApi((c) => c.recipes.restore(asId(id))),
  duplicate: (id) => callApi((c) => c.recipes.duplicate(asId(id))),
  cooked: (id, on) => callApi((c) => c.recipes.cooked({ ...asId(id), payload: { on } })),
  saveImport,
};

/** The model's per-serving estimate from ingredient lines. Nothing is saved. */
export const estimateMacros = (input: MacroEstimateInput) =>
  callApi((c) => c.recipes.estimateMacros({ payload: input }));

/** Today in the cook's own calendar, `YYYY-MM-DD`. */
export const localToday = (now = new Date()) =>
  `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
