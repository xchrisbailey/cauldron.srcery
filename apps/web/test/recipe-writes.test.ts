import {
  copy,
  InvalidRequest,
  type PlanEntry,
  type PlanEntryId,
  type Recipe,
  type RecipeInput,
  toPlanRecipe,
} from "@cauldron/shared";
import { QueryClient, type QueryKey } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vite-plus/test";
import { gatherKeys } from "../src/lib/gather.ts";
import { importKeys } from "../src/lib/imports.ts";
import { planKeys } from "../src/lib/plan.ts";
import type { Notify } from "../src/lib/plan-writes.ts";
import { makeRecipeWrites } from "../src/lib/recipe-writes.ts";
import { type LibraryFilters, recipeKeys } from "../src/lib/recipes.ts";
import { memoryRecipeApi, recipeFrom } from "./memory-recipe-api.ts";

const THIS = "2026-09-28";
const TODAY = "2026-09-30";
const STEW_ID = "00000000-0000-4000-8000-000000000001";
const JOB = "00000000-0000-4000-a000-000000000001";

const input = (title: string, extra: Partial<RecipeInput> = {}): RecipeInput => ({
  title,
  description: null,
  servings: 4,
  prepMinutes: null,
  cookMinutes: null,
  totalMinutes: 90,
  sourcePlatform: "manual",
  sourceUrl: null,
  sourceAuthor: null,
  notes: null,
  photoKey: null,
  tags: [],
  ingredients: [],
  steps: [],
  ...extra,
});

const stew = recipeFrom(STEW_ID, input("Stew"));

const planned = (id: number, recipe: Recipe | null): PlanEntry => ({
  id: `00000000-0000-4000-8000-${String(id).padStart(12, "0")}` as PlanEntryId,
  date: TODAY,
  slot: "dinner",
  title: recipe?.title ?? `Meal ${id}`,
  recipe: recipe ? toPlanRecipe(recipe) : null,
  servings: null,
  position: id,
  brewed: false,
});

const library: LibraryFilters = { q: "", tag: undefined, sort: "recent" };

/**
 * The writes over a real QueryClient and the API in memory, with every query a
 * recipe can show up in already cached: its own, the library, a search, the
 * tags, this week (stew and a free-text meal) and its Gather list.
 */
function setup() {
  const cache = new QueryClient();
  const server = memoryRecipeApi([stew]);
  const notify = vi.fn<Notify>();
  const writes = makeRecipeWrites({ cache, api: server.api, notify, today: () => TODAY });

  cache.setQueryData(recipeKeys.detail(stew.id), stew);
  cache.setQueryData(recipeKeys.list(library), { pages: [], pageParams: [] });
  cache.setQueryData(recipeKeys.search("st"), []);
  cache.setQueryData(recipeKeys.tags, []);
  cache.setQueryData(planKeys.week(THIS), [planned(0, stew), planned(1, null)]);
  cache.setQueryData(gatherKeys.week(THIS), { items: [], recipeCount: 1 });
  cache.setQueryData(importKeys.detail(JOB), { id: JOB });

  const keys = {
    library: recipeKeys.list(library),
    search: recipeKeys.search("st"),
    tags: recipeKeys.tags,
    week: planKeys.week(THIS),
    gather: gatherKeys.week(THIS),
    job: importKeys.detail(JOB),
  } satisfies Record<string, QueryKey>;
  type Name = keyof typeof keys;
  /** The cached queries (of those above) that a write marked stale. */
  const stale = () =>
    (Object.keys(keys) as Array<Name>).filter(
      (name) => cache.getQueryState(keys[name])?.isInvalidated,
    );
  const detail = (id: string) => cache.getQueryData<Recipe>(recipeKeys.detail(id));
  const week = () => cache.getQueryData<ReadonlyArray<PlanEntry>>(planKeys.week(THIS));
  return { cache, server, notify, writes, stale, detail, week };
}

describe("makeRecipeWrites", () => {
  it("caches a new recipe and refreshes the library and tags", async () => {
    const { writes, stale, detail } = setup();
    const made = await writes.create(input("Soup", { tags: ["winter"] }));
    expect(detail(made.id)?.title).toBe("Soup");
    expect(stale()).toEqual(["library", "search", "tags"]);
  });

  it("shows a renamed recipe in the week at once, then refreshes what's built from it", async () => {
    const { writes, stale, detail, week } = setup();
    await writes.update(stew.id, input("Beef stew", { servings: 6 }));
    expect(detail(stew.id)?.title).toBe("Beef stew");
    const [ofStew, freeText] = week()!;
    expect(ofStew?.recipe).toMatchObject({ title: "Beef stew", servings: 6 });
    expect(freeText).toEqual(planned(1, null));
    expect(stale()).toEqual(["library", "search", "tags", "week", "gather"]);
  });

  it("leaves the cache alone when an update is refused", async () => {
    const { server, writes, stale, detail, week } = setup();
    server.failNext("update", new InvalidRequest({ message: "Give it a title." }));
    await expect(writes.update(stew.id, input(""))).rejects.toBeInstanceOf(InvalidRequest);
    expect(detail(stew.id)).toBe(stew);
    expect(week()?.[0]?.recipe?.title).toBe("Stew");
    expect(stale()).toEqual([]);
  });

  it("drops a banished recipe and refreshes everywhere it showed, with Undo", async () => {
    const { cache, server, notify, writes, stale, detail } = setup();
    expect(await writes.banish(stew)).toBe(true);
    expect(cache.getQueryState(recipeKeys.detail(stew.id))).toBeUndefined();
    expect(stale()).toEqual(["library", "search", "tags", "week", "gather"]);
    expect(notify).toHaveBeenCalledWith(copy.recipeView.banished("Stew").text, "info", {
      label: copy.recipeView.undo.text,
      onClick: expect.any(Function),
    });

    // Undo restores it.
    notify.mock.calls[0]?.[2]?.onClick();
    await vi.waitFor(() => expect(detail(stew.id)?.deletedAt).toBeNull());
    expect(server.get(stew.id)?.deletedAt).toBeNull();
    expect(notify).toHaveBeenLastCalledWith(copy.recipeView.restored.text);
  });

  it("keeps the recipe when a banish is refused, and says so", async () => {
    const { server, notify, writes, stale, detail } = setup();
    server.failNext("banish", new Error("offline"));
    expect(await writes.banish(stew)).toBe(false);
    expect(detail(stew.id)).toBe(stew);
    expect(stale()).toEqual([]);
    expect(notify).toHaveBeenCalledWith(copy.errors.internal.text, "error");
  });

  it("caches a restored recipe and refreshes everywhere it shows", async () => {
    const { server, notify, writes, stale, detail } = setup();
    await server.api.banish(stew.id);
    expect(await writes.restore(stew.id)).toBe(true);
    expect(detail(stew.id)?.deletedAt).toBeNull();
    expect(stale()).toEqual(["library", "search", "tags", "week", "gather"]);
    expect(notify).toHaveBeenCalledWith(copy.recipeView.restored.text);
  });

  it("caches a duplicate as a new recipe, leaving the week alone", async () => {
    const { writes, stale, detail } = setup();
    const made = await writes.duplicate(stew.id);
    expect(made.id).not.toBe(stew.id);
    expect(detail(made.id)?.title).toBe("Stew (copy)");
    expect(detail(stew.id)).toBe(stew);
    expect(stale()).toEqual(["library", "search", "tags"]);
  });

  it("marks a recipe brewed today, refreshing the library and the week", async () => {
    const { notify, writes, stale, detail } = setup();
    expect(await writes.brewed(stew.id)).toBe(true);
    expect(detail(stew.id)?.lastCookedOn).toBe(TODAY);
    expect(stale()).toEqual(["library", "week"]);
    expect(notify).toHaveBeenCalledWith(copy.recipeView.brewedToday.text);
  });

  it("says so when marking brewed is refused", async () => {
    const { server, notify, writes, stale, detail } = setup();
    server.failNext("cooked", new Error("offline"));
    expect(await writes.brewed(stew.id)).toBe(false);
    expect(detail(stew.id)?.lastCookedOn).toBeNull();
    expect(stale()).toEqual([]);
    expect(notify).toHaveBeenCalledWith(copy.brewing.couldntSave.text, "error");
  });

  it("caches an import's recipe and refreshes the job", async () => {
    const { writes, stale, detail } = setup();
    const made = await writes.saveImport(JOB, input("Imported curry"));
    expect(detail(made.id)?.title).toBe("Imported curry");
    expect(stale()).toEqual(["library", "search", "tags", "job"]);
  });
});
