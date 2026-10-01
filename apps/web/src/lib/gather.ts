import type { GatherItem, GatherItemId, GatherItemUpdate, GatherList } from "@cauldron/shared";
import { queryOptions } from "@tanstack/react-query";
import { callApi } from "./api";

// The Gather list for TanStack Query. Keys start with "gather", which every
// plan write and recipe edit invalidates, so changes to the week show up here.

export const gatherKeys = {
  all: ["gather"] as const,
  week: (start: string) => ["gather", start] as const,
};

export const gatherQuery = (start: string) =>
  queryOptions({
    queryKey: gatherKeys.week(start),
    queryFn: () => callApi((c) => c.gather.week({ params: { weekStart: start } })),
  });

export const addGatherItem = (start: string, line: string) =>
  callApi((c) => c.gather.add({ params: { weekStart: start }, payload: { line } }));

export const updateGatherItem = (id: string, update: GatherItemUpdate) =>
  callApi((c) => c.gather.update({ params: { id: id as GatherItemId }, payload: update }));

export const removeGatherItem = (id: string) =>
  callApi((c) => c.gather.remove({ params: { id: id as GatherItemId } }));

/** The list with one item changed. A pantry mark applies to every item with the same key. */
export function applyItemUpdate(
  list: GatherList,
  id: string,
  update: GatherItemUpdate,
): GatherList {
  const target = list.items.find((i) => i.id === id);
  if (!target) return list;
  return {
    ...list,
    items: list.items.map((item): GatherItem => ({
      ...item,
      ...(item.id === id && update.checked !== undefined ? { checked: update.checked } : {}),
      ...(item.itemKey === target.itemKey && update.inPantry !== undefined
        ? { inPantry: update.inPantry }
        : {}),
    })),
  };
}

/** Counts for the week's summary bar: every item on the list, and how many are already at home. */
export const summarize = (list: GatherList) => ({
  items: list.items.length,
  recipes: list.recipeCount,
  inPantry: list.items.filter((i) => i.inPantry).length,
});
