import {
  NotFound,
  Recipe,
  type RecipeId,
  type RecipeInput,
  Tag,
  type TagId,
} from "@cauldron/shared";
import type { RecipeApi } from "../src/lib/recipe-writes.ts";

// The recipe API in memory, for tests: it keeps recipes the way the real one
// does (a banished recipe reads as not found until it's restored) and rejects
// with the same typed errors callApi does.

type Op = keyof RecipeApi;

const at = new Date("2026-09-30T12:00:00Z");

type Fields = ConstructorParameters<typeof Recipe>[0];

/** The same recipe with `change` applied, as a new instance. */
const changed = (recipe: Recipe, change: Partial<Fields>): Recipe =>
  new Recipe({
    id: recipe.id,
    title: recipe.title,
    description: recipe.description,
    servings: recipe.servings,
    prepMinutes: recipe.prepMinutes,
    cookMinutes: recipe.cookMinutes,
    totalMinutes: recipe.totalMinutes,
    photoKey: recipe.photoKey,
    macros: recipe.macros,
    tags: recipe.tags,
    lastCookedOn: recipe.lastCookedOn,
    createdAt: recipe.createdAt,
    updatedAt: recipe.updatedAt,
    sourcePlatform: recipe.sourcePlatform,
    sourceUrl: recipe.sourceUrl,
    sourceAuthor: recipe.sourceAuthor,
    notes: recipe.notes,
    ingredients: recipe.ingredients,
    steps: recipe.steps,
    deletedAt: recipe.deletedAt,
    ...change,
  });

/** A recipe as the API would return it, with `input`'s fields. */
export const recipeFrom = (id: string, input: Partial<RecipeInput>): Recipe =>
  new Recipe({
    id: id as RecipeId,
    title: input.title ?? "Untitled",
    description: input.description ?? null,
    servings: input.servings ?? null,
    prepMinutes: input.prepMinutes ?? null,
    cookMinutes: input.cookMinutes ?? null,
    totalMinutes: input.totalMinutes ?? null,
    photoKey: input.photoKey ?? null,
    macros: {
      calories: input.macros?.calories ?? null,
      protein: input.macros?.protein ?? null,
      carbs: input.macros?.carbs ?? null,
      fat: input.macros?.fat ?? null,
    },
    tags: (input.tags ?? []).map(
      (name, i) =>
        new Tag({
          id: `00000000-0000-4000-9000-${String(i).padStart(12, "0")}` as TagId,
          name,
          kind: "other",
        }),
    ),
    lastCookedOn: null,
    createdAt: at,
    updatedAt: at,
    sourcePlatform: input.sourcePlatform ?? "manual",
    sourceUrl: input.sourceUrl ?? null,
    sourceAuthor: input.sourceAuthor ?? null,
    notes: input.notes ?? null,
    ingredients: [],
    steps: [],
    deletedAt: null,
  });

export function memoryRecipeApi(seed: ReadonlyArray<Recipe> = []) {
  const recipes = new Map<string, Recipe>(seed.map((r) => [r.id, r]));
  const failures = new Map<Op, Array<unknown>>();
  let next = 100;

  const newId = () => `00000000-0000-4000-8000-${String(next++).padStart(12, "0")}`;

  /** A live recipe, or NotFound. */
  const live = (id: string) => {
    const recipe = recipes.get(id);
    if (!recipe || recipe.deletedAt) throw new NotFound({ message: "Not found." });
    return recipe;
  };

  const keep = (recipe: Recipe) => {
    recipes.set(recipe.id, recipe);
    return recipe;
  };

  /** Runs `write` as the API would, failing first if a failure is queued for `op`. */
  const call =
    <A extends ReadonlyArray<unknown>>(op: Op, write: (...args: A) => Recipe) =>
    async (...args: A): Promise<Recipe> => {
      await Promise.resolve();
      const failure = failures.get(op)?.shift();
      if (failure) throw failure;
      return write(...args);
    };

  const api: RecipeApi = {
    create: call("create", (input) => keep(recipeFrom(newId(), input))),
    update: call("update", (id, input) => {
      live(id);
      return keep(recipeFrom(id, input));
    }),
    banish: call("banish", (id) => keep(changed(live(id), { deletedAt: at }))),
    restore: call("restore", (id) => {
      const recipe = recipes.get(id);
      if (!recipe) throw new NotFound({ message: "Not found." });
      return keep(changed(recipe, { deletedAt: null }));
    }),
    duplicate: call("duplicate", (id) => {
      const recipe = live(id);
      return keep(changed(recipe, { id: newId() as RecipeId, title: `${recipe.title} (copy)` }));
    }),
    cooked: call("cooked", (id, on) => keep(changed(live(id), { lastCookedOn: on }))),
    saveImport: call("saveImport", (_jobId, input) => keep(recipeFrom(newId(), input))),
  };

  return {
    api,
    /** The recipe as the server holds it now. */
    get: (id: string) => recipes.get(id),
    /** The next call to `op` fails with `error`. */
    failNext: (op: Op, error: unknown) => failures.set(op, [...(failures.get(op) ?? []), error]),
  };
}
