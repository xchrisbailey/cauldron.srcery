import {
  copy,
  dayTotals,
  type DiaryDay,
  type DiaryEntry,
  type DiaryEntryId,
  type DiaryEntryInput,
  type DiaryEntryUpdate,
  MEAL_SLOTS,
  type RecipeId,
} from "@cauldron/shared";
import { useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";
import { useToast } from "../components/ui";
import { messageOr } from "./api-failure";
import { trackerApi, trackerKeys } from "./tracker";

// Diary writes. Each one changes the cached day at once (so the header and
// subtotals move straight away), then settles with what the API says and
// rolls back if it refuses.

const slotOrder = (entry: DiaryEntry) => MEAL_SLOTS.indexOf(entry.slot);

const sorted = (entries: ReadonlyArray<DiaryEntry>) =>
  [...entries].sort((a, b) => slotOrder(a) - slotOrder(b) || a.position - b.position);

/** The day with `entries` in place of its own, and its totals worked out again. */
export const withEntries = (day: DiaryDay, entries: ReadonlyArray<DiaryEntry>): DiaryDay => {
  const mine = sorted(entries.filter((e) => e.date === day.date));
  return { ...day, entries: mine, totals: dayTotals(mine) };
};

/** What an input will look like once logged, for showing it before the API answers. */
export const draftEntry = (
  input: DiaryEntryInput & { id: DiaryEntryId },
  position: number,
): DiaryEntry => ({
  id: input.id,
  date: input.date,
  slot: input.slot,
  name: input.name ?? "",
  amount: input.amount ?? null,
  servings: input.servings,
  macros: input.macros ?? { calories: null, protein: null, carbs: null, fat: null },
  source: input.source,
  recipeId: (input.recipeId ?? null) as RecipeId | null,
  position,
});

export function useDiaryWrites() {
  const cache = useQueryClient();
  const notify = useToast();

  return useMemo(() => {
    const write = (date: string, f: (day: DiaryDay) => DiaryDay) =>
      cache.setQueryData<DiaryDay>(trackerKeys.day(date), (day) => (day ? f(day) : day));

    /**
     * Holds the days touched, runs the write, and on failure takes back only
     * this write's own change, so another write still in flight keeps its.
     */
    const run = async <T>(
      dates: ReadonlyArray<string>,
      apply: () => void,
      revert: () => void,
      call: () => Promise<T>,
    ) => {
      const unique = [...new Set(dates)];
      await Promise.all(unique.map((d) => cache.cancelQueries({ queryKey: trackerKeys.day(d) })));
      apply();
      try {
        const result = await call();
        return result;
      } catch (error) {
        revert();
        notify(messageOr(error, copy.tracker.diary.couldntSave.text), "error");
        return null;
      } finally {
        await Promise.all(
          unique.map((d) => cache.invalidateQueries({ queryKey: trackerKeys.day(d) })),
        );
        void cache.invalidateQueries({ queryKey: trackerKeys.intake });
      }
    };

    /** Logs one or more entries, all or none. Resolves to whether they landed. */
    const add = async (inputs: ReadonlyArray<DiaryEntryInput>, quiet = false) => {
      const withIds = inputs.map((input) => ({
        ...input,
        id: input.id ?? (crypto.randomUUID() as DiaryEntryId),
      }));
      const result = await run(
        withIds.map((i) => i.date),
        () => {
          for (const input of withIds) {
            write(input.date, (day) =>
              withEntries(day, [...day.entries, draftEntry(input, 10_000 + day.entries.length)]),
            );
          }
        },
        () => {
          const drafts = new Set<string>(withIds.map((i) => i.id));
          for (const input of withIds) {
            write(input.date, (day) =>
              withEntries(
                day,
                day.entries.filter((e) => !drafts.has(e.id)),
              ),
            );
          }
        },
        (): Promise<unknown> =>
          withIds.length === 1 ? trackerApi.add(withIds[0]!) : trackerApi.addMany(withIds),
      );
      if (result === null) return false;
      if (!quiet) {
        notify(
          withIds.length === 1
            ? copy.tracker.diary.logged(withIds[0]!.name ?? "").text
            : copy.tracker.diary.loggedMany(withIds.length).text,
        );
      }
      return true;
    };

    const update = (entry: DiaryEntry, change: DiaryEntryUpdate) => {
      const next: DiaryEntry = {
        ...entry,
        ...change,
        amount: change.amount === undefined ? entry.amount : (change.amount ?? null),
        macros: change.macros ?? entry.macros,
      };
      return run(
        [entry.date, next.date],
        () => {
          write(entry.date, (day) =>
            withEntries(
              day,
              day.entries.filter((e) => e.id !== entry.id),
            ),
          );
          write(next.date, (day) =>
            withEntries(day, [...day.entries.filter((e) => e.id !== entry.id), next]),
          );
        },
        () => {
          write(next.date, (day) =>
            withEntries(
              day,
              day.entries.filter((e) => e.id !== entry.id),
            ),
          );
          write(entry.date, (day) =>
            withEntries(day, [...day.entries.filter((e) => e.id !== entry.id), entry]),
          );
        },
        () => trackerApi.update(entry.id, change),
      );
    };

    const remove = async (entry: DiaryEntry) => {
      const gone = await run(
        [entry.date],
        () =>
          write(entry.date, (day) =>
            withEntries(
              day,
              day.entries.filter((e) => e.id !== entry.id),
            ),
          ),
        () =>
          write(entry.date, (day) =>
            withEntries(day, [...day.entries.filter((e) => e.id !== entry.id), entry]),
          ),
        () => trackerApi.remove(entry.id),
      );
      if (gone === null) return;
      notify(copy.tracker.diary.removed(entry.name).text, "info", {
        label: copy.tracker.diary.undo.text,
        onClick: () =>
          void add(
            [
              {
                date: entry.date,
                slot: entry.slot,
                name: entry.name,
                amount: entry.amount,
                servings: entry.servings,
                macros: entry.macros,
                source: entry.source,
                recipeId: entry.recipeId,
              },
            ],
            true,
          ),
      });
    };

    return { add, update, remove };
  }, [cache, notify]);
}

export type DiaryWrites = ReturnType<typeof useDiaryWrites>;
