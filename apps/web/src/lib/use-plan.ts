import {
  copy,
  type PlanEntry,
  type PlanEntryInput,
  type PlanEntryUpdate,
  startOfWeek,
  type WeekStartDay,
} from "@cauldron/shared";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useToast } from "../components/ui";
import {
  addEntry,
  applyRemove,
  applyUpdate,
  inSlot,
  pendingEntry,
  planKeys,
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

/** The API refused for a reason the cook can act on. */
const isInvalid = (error: unknown) =>
  typeof error === "object" && error !== null && "_tag" in error && error._tag === "InvalidRequest";

/**
 * Optimistic plan writes for the week starting `weekStart`: the cached week
 * changes at once, rolls back if the API refuses, and is refetched (with the
 * Gather list) when the write settles. A flaky connection gets two retries.
 */
export function usePlanWrites(weekStart: string, startsOn: WeekStartDay) {
  const queryClient = useQueryClient();
  const toast = useToast();

  /** The cached week an entry on `date` belongs to. */
  const keyFor = (date: string) => planKeys.week(startOfWeek(date, startsOn));

  const snapshot = async (dates: ReadonlyArray<string>) => {
    const keys = [...new Set(dates.map((d) => JSON.stringify(keyFor(d))))].map(
      (k) => JSON.parse(k) as ReturnType<typeof keyFor>,
    );
    await Promise.all(keys.map((queryKey) => queryClient.cancelQueries({ queryKey })));
    return keys.map((queryKey) => [queryKey, queryClient.getQueryData<Week>(queryKey)] as const);
  };

  const rollback = (saved: ReadonlyArray<readonly [ReadonlyArray<string>, Week | undefined]>) => {
    for (const [queryKey, data] of saved) queryClient.setQueryData(queryKey, data);
  };

  const failed = (error: unknown) =>
    toast(isInvalid(error) ? copy.week.slotFull.text : copy.week.couldntSave.text, "error");

  const add = useMutation({
    mutationFn: ({ input }: { input: PlanEntryInput; recipe: StirRecipe | null }) =>
      addEntry(input),
    retry: (count, error) => !isInvalid(error) && count < 2,
    onMutate: async ({ input, recipe }) => {
      const saved = await snapshot([input.date]);
      queryClient.setQueryData<Week>(keyFor(input.date), (week) => {
        if (!week) return week;
        const position = inSlot(week, input.date, input.slot).length;
        return [...week, pendingEntry(input, recipe, position)];
      });
      return saved;
    },
    onError: (error, _vars, saved) => {
      if (saved) rollback(saved);
      failed(error);
    },
    onSettled: () => settlePlan(queryClient),
  });

  const update = useMutation({
    mutationFn: ({ entry, update }: { entry: PlanEntry; update: PlanEntryUpdate }) =>
      updateEntry(entry.id, update),
    retry: (count, error) => !isInvalid(error) && count < 2,
    onMutate: async ({ entry, update }) => {
      const to = update.date ?? entry.date;
      const saved = await snapshot([entry.date, to]);
      if (keyFor(to)[1] === keyFor(entry.date)[1]) {
        queryClient.setQueryData<Week>(keyFor(to), (week) =>
          week ? applyUpdate(week, entry.id, update) : week,
        );
      } else {
        // Moved into another week: out of this one, onto the end of the other's slot.
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
    mutationFn: (entry: PlanEntry) => removeEntry(entry.id),
    retry: 2,
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
          add.mutate({
            input: {
              date: entry.date,
              slot: entry.slot,
              position: entry.position,
              servings: entry.servings,
              ...(entry.recipe ? { recipeId: entry.recipe.id } : { title: entry.title }),
            },
            recipe: entry.recipe,
          }),
      });
    },
    onSettled: () => settlePlan(queryClient),
  });

  return { add, update, remove, weekStart };
}
