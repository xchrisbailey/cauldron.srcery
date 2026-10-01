import {
  copy,
  type PlanEntry,
  type PlanEntryId,
  type PlanEntryInput,
  type PlanEntryUpdate,
  startOfWeek,
  type WeekStartDay,
} from "@cauldron/shared";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useToast } from "../components/ui";
import {
  addEntry,
  applyAdd,
  applyRemove,
  applyUpdate,
  confirmPending,
  inSlot,
  pendingEntry,
  planKeys,
  planMutationKey,
  removeEntry,
  settlePlan,
  updateEntry,
} from "./plan";

type Week = ReadonlyArray<PlanEntry>;

export interface StirRecipe {
  readonly id: string;
  readonly title: string;
  readonly servings: number | null;
  readonly totalMinutes: number | null;
}

type AddVars = { input: PlanEntryInput & { id: PlanEntryId }; recipe: StirRecipe | null };

const tagOf = (error: unknown) =>
  typeof error === "object" && error !== null && "_tag" in error ? error._tag : undefined;

/** The API refused the request itself; retrying won't help. */
const refused = (error: unknown) =>
  tagOf(error) === "InvalidRequest" || tagOf(error) === "NotFound";

const retry = (count: number, error: unknown) => !refused(error) && count < 2;

/**
 * Optimistic plan writes: the cached week changes at once, rolls back if the
 * API refuses, and is refetched (with the Gather list) once the last write
 * settles. Every write is safe to retry on a flaky connection: adds carry
 * their own id, and removing what's already gone counts as done.
 */
export function usePlanWrites(startsOn: WeekStartDay) {
  const queryClient = useQueryClient();
  const toast = useToast();

  const weekOf = (date: string) => startOfWeek(date, startsOn);
  const keyFor = (date: string) => planKeys.week(weekOf(date));

  const snapshot = async (dates: ReadonlyArray<string>) => {
    const weeks = [...new Set(dates.map(weekOf))];
    await Promise.all(weeks.map((w) => queryClient.cancelQueries({ queryKey: planKeys.week(w) })));
    return weeks.map(
      (w) => [planKeys.week(w), queryClient.getQueryData<Week>(planKeys.week(w))] as const,
    );
  };

  const rollback = (saved: ReadonlyArray<readonly [ReadonlyArray<string>, Week | undefined]>) => {
    for (const [queryKey, data] of saved) queryClient.setQueryData(queryKey, data);
  };

  // An InvalidRequest carries a plain message saying why ("That meal is full").
  const failed = (error: unknown) =>
    toast(
      tagOf(error) === "InvalidRequest" && error instanceof Error && error.message
        ? error.message
        : copy.week.couldntSave.text,
      "error",
    );

  const add = useMutation({
    mutationKey: planMutationKey,
    mutationFn: ({ input }: AddVars) => addEntry(input),
    retry,
    onMutate: async ({ input, recipe }: AddVars) => {
      const saved = await snapshot([input.date]);
      queryClient.setQueryData<Week>(keyFor(input.date), (week) => {
        if (!week) return week;
        const end = inSlot(week, input.date, input.slot).length;
        return applyAdd(week, pendingEntry(input, recipe, input.position ?? end));
      });
      return saved;
    },
    onError: (error, _vars, saved) => {
      if (saved) rollback(saved);
      failed(error);
    },
    onSettled: (_entry, _error, { input }) => {
      confirmPending(input.id);
      settlePlan(queryClient);
    },
  });

  /** Stir in a recipe (with `recipeId`) or a free-text meal (with `title`). */
  const stir = (input: PlanEntryInput, recipe: StirRecipe | null) =>
    add.mutate({ input: { ...input, id: crypto.randomUUID() as PlanEntryId }, recipe });

  const update = useMutation({
    mutationKey: planMutationKey,
    mutationFn: ({ entry, update }: { entry: PlanEntry; update: PlanEntryUpdate }) =>
      updateEntry(entry.id, update),
    retry,
    onMutate: async ({ entry, update }) => {
      const to = update.date ?? entry.date;
      const saved = await snapshot([entry.date, to]);
      if (weekOf(to) === weekOf(entry.date)) {
        queryClient.setQueryData<Week>(keyFor(to), (week) =>
          week ? applyUpdate(week, entry.id, update) : week,
        );
      } else {
        // Moved into another week: out of this one, into the other's slot.
        queryClient.setQueryData<Week>(keyFor(entry.date), (week) =>
          week ? applyRemove(week, entry.id) : week,
        );
        queryClient.setQueryData<Week>(keyFor(to), (week) =>
          week ? applyUpdate([...week, { ...entry, date: to }], entry.id, update) : week,
        );
      }
      return saved;
    },
    onError: (error, _vars, saved) => {
      if (saved) rollback(saved);
      failed(error);
    },
    onSettled: () => settlePlan(queryClient),
  });

  const remove = useMutation({
    mutationKey: planMutationKey,
    // A retried remove that already landed finds nothing to remove: that's done too.
    mutationFn: (entry: PlanEntry) =>
      removeEntry(entry.id).catch((error: unknown) => {
        if (tagOf(error) === "NotFound") return entry;
        throw error;
      }),
    retry,
    onMutate: async (entry) => {
      const saved = await snapshot([entry.date]);
      queryClient.setQueryData<Week>(keyFor(entry.date), (week) =>
        week ? applyRemove(week, entry.id) : week,
      );
      return saved;
    },
    onError: (error, _vars, saved) => {
      if (saved) rollback(saved);
      failed(error);
    },
    onSuccess: (_removed, entry) => {
      toast(copy.week.removed(entry.recipe?.title ?? entry.title).text, "info", {
        label: copy.week.undo.text,
        onClick: () =>
          stir(
            {
              date: entry.date,
              slot: entry.slot,
              position: entry.position,
              servings: entry.servings,
              ...(entry.recipe ? { recipeId: entry.recipe.id } : { title: entry.title }),
            },
            entry.recipe,
          ),
      });
    },
    onSettled: () => settlePlan(queryClient),
  });

  return { stir, update, remove };
}
