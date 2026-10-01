import {
  addDays,
  copy,
  type PlanEntry,
  type PlanEntryId,
  type PlanEntryInput,
  type PlanEntryUpdate,
  type PlanRecipe,
  startOfWeek,
  type WeekStartDay,
} from "@cauldron/shared";
import {
  MutationObserver,
  type MutationObserverOptions,
  type QueryClient,
} from "@tanstack/react-query";
import { failureOf, messageOr, retryWhile } from "./api-failure";
import {
  applyAdd,
  applyRemove,
  applyUpdate,
  confirmPending,
  inSlot,
  pendingEntry,
  planKeys,
} from "./plan";

// Every write to the week goes through here. The cached week changes at once,
// rolls back if the API refuses, and is refetched (with the Gather list) once
// the last write settles. Every write that can be retried is safe to retry on
// a flaky connection: adds carry their own id, and removing what's already
// gone counts as done. It knows nothing about React: the hook in use-plan.ts
// hands it the QueryClient and the toast.

type Week = ReadonlyArray<PlanEntry>;

/** The plan endpoints the writes call. `planApi` in plan.ts is the real one. */
export interface PlanApi {
  readonly add: (input: PlanEntryInput) => Promise<PlanEntry>;
  readonly addMany: (inputs: ReadonlyArray<PlanEntryInput>) => Promise<ReadonlyArray<PlanEntry>>;
  readonly update: (id: PlanEntryId, update: PlanEntryUpdate) => Promise<PlanEntry>;
  readonly remove: (id: PlanEntryId) => Promise<PlanEntry>;
  /** Copies the week from `from` into the week from `to`, and returns the target week. */
  readonly copy: (from: string, to: string) => Promise<ReadonlyArray<PlanEntry>>;
  /** Removes every entry in the week from `start`. */
  readonly clear: (start: string) => Promise<ReadonlyArray<PlanEntry>>;
}

/** A toast, with a button (such as Undo) when there's an `action`. */
export type Notify = (
  message: string,
  tone?: "info" | "error",
  action?: { readonly label: string; readonly onClick: () => void },
) => void;

export interface PlanWritesDeps {
  readonly cache: QueryClient;
  readonly api: PlanApi;
  readonly startsOn: WeekStartDay;
  readonly notify: Notify;
}

/** Plan writes share a key. */
const planMutationKey = ["plan"] as const;
/** Copying a week has its own key (under the plan's), so the page can tell it's running. */
export const copyMutationKey = [...planMutationKey, "copy"] as const;

type Saved = ReadonlyArray<readonly [ReadonlyArray<string>, Week | undefined]>;

const retry = retryWhile(2);

/** Plan writes still running against each cache, from any page or dialog. */
const running = new WeakMap<QueryClient, number>();

/**
 * After a plan write: once it's the last one running, refetch the week and
 * anything built from it. Waiting for the last write means a refetch can't
 * briefly undo a later optimistic edit, and several writes refetch once.
 */
const settle = (cache: QueryClient) => {
  const left = (running.get(cache) ?? 1) - 1;
  running.set(cache, left);
  if (left > 0) return;
  void cache.invalidateQueries({ queryKey: planKeys.all });
  void cache.invalidateQueries({ queryKey: ["gather"] });
};

export function makePlanWrites({ cache, api, startsOn, notify }: PlanWritesDeps) {
  const weekOf = (date: string) => startOfWeek(date, startsOn);
  const keyFor = (date: string) => planKeys.week(weekOf(date));

  /** Stops the weeks `dates` fall in from refetching, and keeps them to roll back to. */
  const snapshot = async (dates: ReadonlyArray<string>): Promise<Saved> => {
    const weeks = [...new Set(dates.map(weekOf))];
    await Promise.all(weeks.map((w) => cache.cancelQueries({ queryKey: planKeys.week(w) })));
    return weeks.map(
      (w) => [planKeys.week(w), cache.getQueryData<Week>(planKeys.week(w))] as const,
    );
  };

  const rollback = (saved: Saved | undefined) => {
    for (const [queryKey, data] of saved ?? []) cache.setQueryData(queryKey, data);
  };

  const edit = (date: string, f: (week: Week) => Week) =>
    cache.setQueryData<Week>(keyFor(date), (week) => (week ? f(week) : week));

  // An InvalidRequest carries a plain message saying why ("That meal is full").
  const failed = (error: unknown) => notify(messageOr(error, copy.week.couldntSave.text), "error");

  /**
   * Runs one write as a plan mutation. Resolves to whether it landed; a
   * failure has already been rolled back and shown.
   */
  const run = <T>(
    options: MutationObserverOptions<T, unknown, void, Saved> & { mutationFn: () => Promise<T> },
  ): Promise<boolean> => {
    running.set(cache, (running.get(cache) ?? 0) + 1);
    const observer = new MutationObserver(cache, {
      mutationKey: planMutationKey,
      retry,
      onError: (error, _vars, saved) => {
        rollback(saved);
        failed(error);
      },
      ...options,
    });
    return observer
      .mutate()
      .then(
        () => true,
        () => false,
      )
      .finally(() => {
        // Detach, so the finished mutation can be collected after gcTime.
        observer.reset();
        settle(cache);
      });
  };

  const withId = (input: PlanEntryInput) => ({
    ...input,
    id: input.id ?? (crypto.randomUUID() as PlanEntryId),
  });

  const place = (input: PlanEntryInput, recipe: PlanRecipe | null) =>
    edit(input.date, (week) => {
      const end = inSlot(week, input.date, input.slot).length;
      return applyAdd(week, pendingEntry(input, recipe, input.position ?? end));
    });

  /** Stir in a recipe (with `recipeId`) or a free-text meal (with `title`). */
  const stir = (entry: PlanEntryInput, recipe: PlanRecipe | null) => {
    const input = withId(entry);
    return run({
      mutationFn: () => api.add(input),
      onMutate: async () => {
        const saved = await snapshot([input.date]);
        place(input, recipe);
        return saved;
      },
      onSettled: () => confirmPending(input.id),
    });
  };

  /** Stir one recipe into several days at once: all of them land, or none do. */
  const spread = (entries: ReadonlyArray<PlanEntryInput>, recipe: PlanRecipe) => {
    const inputs = entries.map(withId);
    return run({
      mutationFn: () => api.addMany(inputs),
      onMutate: async () => {
        const saved = await snapshot(inputs.map((input) => input.date));
        for (const input of inputs) place(input, recipe);
        return saved;
      },
      onSuccess: () => notify(copy.week.spread.stirred(inputs.length).text),
      onSettled: () => {
        for (const input of inputs) confirmPending(input.id);
      },
    });
  };

  /** Change an entry, or move it: to another slot, day, or week. */
  const update = (entry: PlanEntry, change: PlanEntryUpdate) =>
    run({
      mutationFn: () => api.update(entry.id, change),
      onMutate: async () => {
        const to = change.date ?? entry.date;
        const saved = await snapshot([entry.date, to]);
        if (weekOf(to) === weekOf(entry.date)) {
          edit(to, (week) => applyUpdate(week, entry.id, change));
        } else {
          // Moved into another week: out of this one, into the other's slot.
          edit(entry.date, (week) => applyRemove(week, entry.id));
          edit(to, (week) => applyUpdate([...week, { ...entry, date: to }], entry.id, change));
        }
        return saved;
      },
    });

  /** Take an entry off the week, with Undo in the toast. */
  const remove = (entry: PlanEntry) =>
    run({
      // A retried remove that already landed finds nothing to remove: that's done too.
      mutationFn: () =>
        api.remove(entry.id).catch((error: unknown) => {
          if (failureOf(error).tag === "NotFound") return entry;
          throw error;
        }),
      onMutate: async () => {
        const saved = await snapshot([entry.date]);
        edit(entry.date, (week) => applyRemove(week, entry.id));
        return saved;
      },
      onSuccess: () =>
        notify(copy.week.removed(entry.recipe?.title ?? entry.title).text, "info", {
          label: copy.week.undo.text,
          onClick: () =>
            void stir(
              {
                date: entry.date,
                slot: entry.slot,
                position: entry.position,
                servings: entry.servings,
                ...(entry.recipe ? { recipeId: entry.recipe.id } : { title: entry.title }),
              },
              entry.recipe,
            ),
        }),
    });

  /** Copy the week before `start` into it. Not retried: a second copy would plan it all twice. */
  const copyLastWeek = (start: string) => {
    const before = cache.getQueryData<Week>(planKeys.week(start))?.length ?? 0;
    return run({
      mutationKey: copyMutationKey,
      mutationFn: () => api.copy(addDays(start, -7), start),
      retry: false,
      onMutate: () => snapshot([start]),
      onSuccess: (entries) => {
        cache.setQueryData(planKeys.week(start), entries);
        notify(
          entries.length > before ? copy.week.copiedLastWeek.text : copy.week.nothingToCopy.text,
        );
      },
      onError: (error, _vars, saved) => {
        rollback(saved);
        notify(copy.week.couldntSave.text, "error");
      },
    });
  };

  /** Empty the week from `start`. */
  const clear = (start: string) =>
    run({
      mutationFn: () => api.clear(start),
      retry: false,
      onMutate: async () => {
        const saved = await snapshot([start]);
        cache.setQueryData<Week>(planKeys.week(start), []);
        return saved;
      },
      onSuccess: () => notify(copy.week.cleared.text),
      onError: (error, _vars, saved) => {
        rollback(saved);
        notify(copy.week.couldntSave.text, "error");
      },
    });

  return { stir, spread, update, remove, copyLastWeek, clear };
}

export type PlanWrites = ReturnType<typeof makePlanWrites>;
