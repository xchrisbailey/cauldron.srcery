import {
  addDays,
  InvalidRequest,
  NotFound,
  type PlanEntry,
  type PlanEntryId,
  type PlanEntryInput,
  type PlanRecipe,
} from "@cauldron/shared";
import { applyAdd, applyRemove, applyUpdate, inSlot } from "../src/lib/plan.ts";
import type { PlanApi } from "../src/lib/plan-writes.ts";

// The plan API in memory, for tests: it keeps entries the way the real one
// does (an add with a known id returns that entry; removing what's gone is
// NotFound) and rejects with the same typed errors callApi does.

type Op = keyof PlanApi;

interface Failure {
  readonly error: unknown;
  /** The write lands but its answer is lost, as when the connection drops. */
  readonly landed: boolean;
}

export function memoryPlanApi(seed: {
  entries?: ReadonlyArray<PlanEntry>;
  recipes?: ReadonlyArray<PlanRecipe>;
}) {
  let entries: ReadonlyArray<PlanEntry> = seed.entries ?? [];
  const recipes = new Map((seed.recipes ?? []).map((r) => [r.id as string, r]));
  const failures = new Map<Op, Array<Failure>>();
  const calls: Record<Op | "list", number> = {
    add: 0,
    addMany: 0,
    update: 0,
    remove: 0,
    copy: 0,
    clear: 0,
    list: 0,
  };
  let gate: Promise<void> | null = null;

  const toEntry = (input: PlanEntryInput, within: ReadonlyArray<PlanEntry>): PlanEntry => {
    const recipe = input.recipeId ? recipes.get(input.recipeId) : null;
    if (recipe === undefined) throw new InvalidRequest({ message: "No such recipe." });
    return {
      id: input.id ?? (crypto.randomUUID() as PlanEntryId),
      date: input.date,
      slot: input.slot,
      title: recipe?.title ?? input.title ?? "",
      recipe: recipe ?? null,
      servings: input.servings ?? null,
      position: input.position ?? inSlot(within, input.date, input.slot).length,
      brewed: false,
    };
  };

  const insert = (input: PlanEntryInput): PlanEntry => {
    const known = entries.find((e) => e.id === input.id);
    if (known) return known;
    const entry = toEntry(input, entries);
    entries = applyAdd(entries, entry);
    return entries.find((e) => e.id === entry.id)!;
  };

  const inWeek = (start: string) =>
    entries.filter((e) => e.date >= start && e.date <= addDays(start, 6));

  /** Runs `write` as the API would, failing first if a failure is queued for `op`. */
  const call =
    <A extends ReadonlyArray<unknown>, R>(op: Op, write: (...args: A) => R) =>
    async (...args: A): Promise<R> => {
      calls[op]++;
      await gate;
      await Promise.resolve();
      const failure = failures.get(op)?.shift();
      if (failure && !failure.landed) throw failure.error;
      const result = write(...args);
      if (failure) throw failure.error;
      return result;
    };

  const api: PlanApi = {
    add: call("add", insert),
    addMany: call("addMany", (inputs: ReadonlyArray<PlanEntryInput>) => {
      const before = entries;
      try {
        return inputs.map(insert);
      } catch (error) {
        entries = before;
        throw error;
      }
    }),
    update: call("update", (id, update) => {
      if (!entries.some((e) => e.id === id)) throw new NotFound({ message: "Not found." });
      entries = applyUpdate(entries, id, update);
      return entries.find((e) => e.id === id)!;
    }),
    remove: call("remove", (id) => {
      const gone = entries.find((e) => e.id === id);
      if (!gone) throw new NotFound({ message: "Not found." });
      entries = applyRemove(entries, id);
      return gone;
    }),
    copy: call("copy", (from, to) => {
      const shift = Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000);
      for (const e of inWeek(from)) {
        insert({
          date: addDays(e.date, shift),
          slot: e.slot,
          servings: e.servings,
          ...(e.recipe ? { recipeId: e.recipe.id } : { title: e.title }),
        });
      }
      return inWeek(to);
    }),
    clear: call("clear", (start) => {
      const gone = inWeek(start);
      entries = entries.filter((e) => !gone.includes(e));
      return gone;
    }),
  };

  return {
    api,
    calls,
    /** What's planned now, as the server would list it. */
    entries: () => entries,
    /** The week from `start`, as a week query fetches it. */
    list: async (start: string) => {
      calls.list++;
      await Promise.resolve();
      return inWeek(start);
    },
    /** The next call to `op` fails with `error`, after landing when `landed`. */
    failNext: (op: Op, error: unknown, { landed = false } = {}) =>
      failures.set(op, [...(failures.get(op) ?? []), { error, landed }]),
    /** Holds every call until the returned function is called. */
    pause: () => {
      let release = () => {};
      gate = new Promise((resolve) => {
        release = () => {
          gate = null;
          resolve();
        };
      });
      return release;
    },
  };
}
