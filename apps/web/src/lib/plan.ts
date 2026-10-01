import {
  addDays,
  MEAL_SLOTS,
  type MealSlot,
  type PlanEntry,
  type PlanEntryId,
  type PlanEntryInput,
  type PlanEntryUpdate,
  type RecipeId,
  type WeekStartDay,
} from "@cauldron/shared";
import { queryOptions, type QueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { callApi } from "./api";

// The week for TanStack Query. Writes update the cached week straight away
// (optimistically) and roll back if the API refuses; the Gather list for the
// week is refreshed after every change.

export const planKeys = {
  all: ["plan"] as const,
  week: (start: string) => ["plan", start] as const,
};

export const weekQuery = (start: string) =>
  queryOptions({
    queryKey: planKeys.week(start),
    queryFn: () => callApi((c) => c.plan.list({ query: { from: start, to: addDays(start, 6) } })),
  });

export const addEntry = (input: PlanEntryInput) => callApi((c) => c.plan.add({ payload: input }));
export const updateEntry = (id: string, update: PlanEntryUpdate) =>
  callApi((c) => c.plan.update({ params: { id: id as PlanEntryId }, payload: update }));
export const removeEntry = (id: string) =>
  callApi((c) => c.plan.remove({ params: { id: id as PlanEntryId } }));
export const copyWeek = (from: string, to: string) =>
  callApi((c) => c.plan.copy({ payload: { from, to } }));
export const clearWeek = (start: string) =>
  callApi((c) => c.plan.clear({ payload: { from: start, to: addDays(start, 6) } }));

/** Entries in one day's slot, in order. */
export const inSlot = (entries: ReadonlyArray<PlanEntry>, date: string, slot: MealSlot) =>
  entries.filter((e) => e.date === date && e.slot === slot).sort((a, b) => a.position - b.position);

const slotOrder = (slot: MealSlot) => MEAL_SLOTS.indexOf(slot);

/** Day, then meal, then position: the order the API returns. */
const sorted = (entries: ReadonlyArray<PlanEntry>) =>
  [...entries].sort(
    (a, b) =>
      a.date.localeCompare(b.date) ||
      slotOrder(a.slot) - slotOrder(b.slot) ||
      a.position - b.position,
  );

/** Rewrites positions 0..n in one slot after an insert or removal. */
const renumber = (entries: Array<PlanEntry>, date: string, slot: MealSlot, order: Array<string>) =>
  entries.map((e) =>
    e.date === date && e.slot === slot && order.includes(e.id)
      ? { ...e, position: order.indexOf(e.id) }
      : e,
  );

/**
 * What the week looks like after `update`, as the API will compute it: a move
 * lands at `position` (or the end of a new slot) and both slots are renumbered.
 */
export function applyUpdate(
  entries: ReadonlyArray<PlanEntry>,
  id: string,
  update: PlanEntryUpdate,
): ReadonlyArray<PlanEntry> {
  const current = entries.find((e) => e.id === id);
  if (!current) return entries;
  let next: Array<PlanEntry> = entries.map((e) =>
    e.id === id
      ? {
          ...e,
          ...(update.servings === undefined ? {} : { servings: update.servings }),
          ...(update.title === undefined ? {} : { title: update.title }),
        }
      : e,
  );
  if (update.date === undefined && update.slot === undefined && update.position === undefined) {
    return next;
  }
  const date = update.date ?? current.date;
  const slot = update.slot ?? current.slot;
  const moved = date !== current.date || slot !== current.slot;
  const siblings = inSlot(next, date, slot)
    .filter((e) => e.id !== id)
    .map((e): string => e.id);
  const index = moved ? siblings.length : current.position;
  const order = siblings.toSpliced(Math.min(update.position ?? index, siblings.length), 0, id);
  next = next.map((e) => (e.id === id ? { ...e, date, slot } : e));
  next = renumber(next, date, slot, order);
  if (moved) {
    const left = inSlot(next, current.date, current.slot).map((e) => e.id);
    next = renumber(next, current.date, current.slot, left);
  }
  return sorted(next);
}

/** The week without `id`, with its old slot renumbered. */
export function applyRemove(entries: ReadonlyArray<PlanEntry>, id: string) {
  const gone = entries.find((e) => e.id === id);
  if (!gone) return entries;
  const rest = entries.filter((e) => e.id !== id);
  return renumber(
    rest,
    gone.date,
    gone.slot,
    inSlot(rest, gone.date, gone.slot).map((e) => e.id),
  );
}

/** A placeholder for an entry the API hasn't confirmed yet. */
export const pendingEntry = (
  input: PlanEntryInput,
  recipe: {
    id: string;
    title: string;
    servings: number | null;
    totalMinutes: number | null;
  } | null,
  position: number,
): PlanEntry => ({
  id: `pending-${Math.random().toString(36).slice(2)}` as PlanEntryId,
  date: input.date,
  slot: input.slot,
  title: recipe?.title ?? input.title ?? "",
  recipe: recipe
    ? {
        id: recipe.id as RecipeId,
        title: recipe.title,
        servings: recipe.servings,
        totalMinutes: recipe.totalMinutes,
        photoKey: null,
      }
    : null,
  servings: input.servings ?? null,
  position,
  brewed: false,
});

export const isPending = (entry: PlanEntry) => entry.id.startsWith("pending-");

/** After any plan write: refetch the week and anything built from it. */
export const settlePlan = (queryClient: QueryClient) => {
  void queryClient.invalidateQueries({ queryKey: planKeys.all });
  void queryClient.invalidateQueries({ queryKey: ["gather"] });
};

const WEEK_START_KEY = "cauldron:week-start";

/** Monday or Sunday, a per-viewer preference remembered in this browser. */
export function useWeekStartDay() {
  const [day, setDay] = useState<WeekStartDay>(1);
  useEffect(() => {
    try {
      const saved = window.localStorage.getItem(WEEK_START_KEY);
      if (saved === "0" || saved === "1") setDay(Number(saved) as WeekStartDay);
    } catch {
      // Storage is optional.
    }
  }, []);
  const choose = (next: WeekStartDay) => {
    setDay(next);
    try {
      window.localStorage.setItem(WEEK_START_KEY, String(next));
    } catch {
      // Storage is optional.
    }
  };
  return [day, choose] as const;
}
