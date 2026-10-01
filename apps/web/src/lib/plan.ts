import {
  addDays,
  MEAL_SLOTS,
  type Macros,
  type MealSlot,
  noMacros,
  type PlanEntry,
  type PlanEntryId,
  type PlanEntryInput,
  type PlanEntryUpdate,
  type RecipeId,
} from "@cauldron/shared";
import { queryOptions, type QueryClient } from "@tanstack/react-query";
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
export const addEntries = (entries: ReadonlyArray<PlanEntryInput>) =>
  callApi((c) => c.plan.addMany({ payload: { entries } }));
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

/** Entries added optimistically that the API hasn't confirmed yet. */
const pendingIds = new Set<string>();

/**
 * A placeholder for an entry the API hasn't confirmed yet. It carries the id
 * the client sends with the add, so a retry can't plan the meal twice and the
 * placeholder turns into the real entry in place.
 */
export const pendingEntry = (
  input: PlanEntryInput,
  recipe: {
    id: string;
    title: string;
    servings: number | null;
    totalMinutes: number | null;
    macros?: Macros;
  } | null,
  position: number,
): PlanEntry => {
  const id = input.id ?? (crypto.randomUUID() as PlanEntryId);
  pendingIds.add(id);
  return {
    id,
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
          macros: recipe.macros ?? noMacros,
        }
      : null,
    servings: input.servings ?? null,
    position,
    brewed: false,
  };
};

export const isPending = (entry: PlanEntry) => pendingIds.has(entry.id);

/** The add for `id` has settled, one way or the other. */
export const confirmPending = (id: string) => pendingIds.delete(id);

/** The week with `entry` inserted at its position in its slot, which is renumbered. */
export function applyAdd(entries: ReadonlyArray<PlanEntry>, entry: PlanEntry) {
  const siblings = inSlot(entries, entry.date, entry.slot).map((e): string => e.id);
  const order = siblings.toSpliced(Math.min(entry.position, siblings.length), 0, entry.id);
  return sorted(renumber([...entries, entry], entry.date, entry.slot, order));
}

/** Plan writes share a key, so the week is only refetched once the last one settles. */
export const planMutationKey = ["plan"] as const;

/**
 * After a plan write: refetch the week and anything built from it. Called from
 * a mutation's onSettled (while it still counts as running), it waits for the
 * last write in flight, so a refetch can't briefly undo a later optimistic edit.
 */
export const settlePlan = (queryClient: QueryClient) => {
  if (queryClient.isMutating({ mutationKey: planMutationKey }) > 1) return;
  void queryClient.invalidateQueries({ queryKey: planKeys.all });
  void queryClient.invalidateQueries({ queryKey: ["gather"] });
};

/**
 * Where a meal dragged onto a slot lands: before `beforeId` when it was dropped
 * on another meal, otherwise at the end. Null when nothing would change, such
 * as a meal dropped on itself or back where it was.
 */
export function dropMove(
  entries: ReadonlyArray<PlanEntry>,
  movingId: string,
  target: { date: string; slot: MealSlot },
  beforeId?: string,
): PlanEntryUpdate | null {
  const moving = entries.find((e) => e.id === movingId);
  if (!moving || beforeId === movingId) return null;
  const siblings = inSlot(entries, target.date, target.slot).filter((e) => e.id !== movingId);
  const index = beforeId === undefined ? -1 : siblings.findIndex((e) => e.id === beforeId);
  const position = index === -1 ? siblings.length : index;
  const stays = moving.date === target.date && moving.slot === target.slot;
  if (stays && position === inSlot(entries, target.date, target.slot).indexOf(moving)) return null;
  return { date: target.date, slot: target.slot, position };
}

/** Where a recipe dropped on a slot goes: before `beforeId`, or the end (undefined). */
export function dropAt(
  entries: ReadonlyArray<PlanEntry>,
  target: { date: string; slot: MealSlot },
  beforeId?: string,
): number | undefined {
  if (beforeId === undefined) return undefined;
  const index = inSlot(entries, target.date, target.slot).findIndex((e) => e.id === beforeId);
  return index === -1 ? undefined : index;
}
