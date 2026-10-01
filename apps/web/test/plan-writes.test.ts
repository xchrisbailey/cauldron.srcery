import {
  copy,
  InvalidRequest,
  noMacros,
  type PlanEntry,
  type PlanEntryId,
  type PlanRecipe,
  type RecipeId,
} from "@cauldron/shared";
import { QueryClient, QueryObserver } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { isPending, planKeys } from "../src/lib/plan.ts";
import { makePlanWrites, type Notify } from "../src/lib/plan-writes.ts";
import { memoryPlanApi } from "./memory-plan-api.ts";

// Monday-start weeks: this one and the next.
const THIS = "2026-09-28";
const NEXT = "2026-10-05";

const stew: PlanRecipe = {
  id: "00000000-0000-4000-8000-000000000001" as RecipeId,
  title: "Stew",
  servings: 4,
  totalMinutes: 90,
  photoKey: null,
  macros: noMacros,
};

const entry = (id: number, date: string, extra: Partial<PlanEntry> = {}): PlanEntry => ({
  id: `00000000-0000-4000-8000-${String(id).padStart(12, "0")}` as PlanEntryId,
  date,
  slot: "dinner",
  title: `Meal ${id}`,
  recipe: null,
  servings: null,
  position: 0,
  brewed: false,
  ...extra,
});

const subscriptions: Array<() => void> = [];
afterEach(() => {
  for (const unsubscribe of subscriptions.splice(0)) unsubscribe();
});

/**
 * The writes over a real QueryClient and the API in memory, with each week in
 * `weeks` on screen (an active query), as the week page has them.
 */
async function setup(
  seed: Parameters<typeof memoryPlanApi>[0] = {},
  weeks: ReadonlyArray<string> = [THIS],
) {
  // No wait between retries, so a retried write runs straight away.
  const cache = new QueryClient({ defaultOptions: { mutations: { retryDelay: 0 } } });
  const server = memoryPlanApi(seed);
  const notify = vi.fn<Notify>();
  for (const start of weeks) {
    const observer = new QueryObserver(cache, {
      queryKey: planKeys.week(start),
      queryFn: () => server.list(start),
    });
    subscriptions.push(observer.subscribe(() => {}));
    await vi.waitFor(() => expect(observer.getCurrentResult().isSuccess).toBe(true));
  }
  const writes = makePlanWrites({ cache, api: server.api, startsOn: 1, notify });
  const week = (start: string) =>
    cache.getQueryData<ReadonlyArray<PlanEntry>>(planKeys.week(start));
  /** Waits for the refetch after the last write to land. */
  const settled = () => vi.waitFor(() => expect(cache.isFetching()).toBe(0));
  return { cache, server, notify, writes, week, settled };
}

describe("makePlanWrites", () => {
  it("restores both weeks when a move into another week is refused", async () => {
    const meal = entry(1, "2026-09-30");
    const other = entry(2, "2026-10-06");
    const { server, notify, writes, week } = await setup({ entries: [meal, other] }, [THIS, NEXT]);
    const before = { this: week(THIS), next: week(NEXT) };
    server.failNext("update", new InvalidRequest({ message: "That meal is full." }));

    const release = server.pause();
    const moving = writes.update(meal, { date: "2026-10-06", position: 0 });
    // Optimistic: it has left this week and landed in the next one's slot.
    await vi.waitFor(() => expect(week(NEXT)?.map((e) => e.id)).toEqual([meal.id, other.id]));
    expect(week(THIS)).toEqual([]);
    release();

    expect(await moving).toBe(false);
    expect(week(THIS)).toEqual(before.this);
    expect(week(NEXT)).toEqual(before.next);
    expect(notify).toHaveBeenCalledWith("That meal is full.", "error");
  });

  it("refetches once, after the last of several writes in flight settles", async () => {
    const { server, writes, settled } = await setup({ entries: [entry(1, "2026-09-29")] });
    expect(server.calls.list).toBe(1);

    const release = server.pause();
    const writing = [
      writes.stir({ date: "2026-09-30", slot: "lunch", title: "Soup" }, null),
      writes.stir({ date: "2026-10-01", slot: "lunch", title: "Salad" }, null),
      writes.update(entry(1, "2026-09-29"), { servings: 2 }),
    ];
    // All three are at the API at once.
    await vi.waitFor(() => expect(server.calls.add + server.calls.update).toBe(3));
    release();
    expect(await Promise.all(writing)).toEqual([true, true, true]);
    await settled();

    expect(server.calls.list).toBe(2);
  });

  it("counts removing an entry that's already gone as done", async () => {
    const gone = entry(1, "2026-09-29");
    const { cache, server, notify, writes, week, settled } = await setup();
    // The page still shows it; the server removed it on an earlier try.
    cache.setQueryData(planKeys.week(THIS), [gone]);

    expect(await writes.remove(gone)).toBe(true);
    expect(server.calls.remove).toBe(1);
    expect(notify).toHaveBeenCalledWith(copy.week.removed("Meal 1").text, "info", {
      label: copy.week.undo.text,
      onClick: expect.any(Function),
    });
    expect(notify).not.toHaveBeenCalledWith(expect.anything(), "error");
    await settled();
    expect(week(THIS)).toEqual([]);
  });

  it("puts a removed entry back with Undo", async () => {
    const meal = entry(1, "2026-09-29", { title: "Stew", recipe: stew, servings: 2 });
    const { server, notify, writes, week, settled } = await setup({
      entries: [meal],
      recipes: [stew],
    });

    expect(await writes.remove(meal)).toBe(true);
    expect(server.entries()).toEqual([]);
    const action = notify.mock.calls.at(-1)?.[2];
    action?.onClick();

    await vi.waitFor(() => expect(server.entries()).toHaveLength(1));
    await settled();
    const back = week(THIS)![0]!;
    expect(back).toMatchObject({ date: meal.date, slot: meal.slot, servings: 2, recipe: stew });
    expect(isPending(back)).toBe(false);
  });

  it("copies last week into this one", async () => {
    const { server, notify, writes, week } = await setup({
      entries: [entry(1, "2026-09-22"), entry(2, "2026-09-24", { slot: "lunch" })],
    });

    expect(await writes.copyLastWeek(THIS)).toBe(true);
    expect(week(THIS)?.map((e) => [e.date, e.slot, e.title])).toEqual([
      ["2026-09-29", "dinner", "Meal 1"],
      ["2026-10-01", "lunch", "Meal 2"],
    ]);
    expect(server.calls.copy).toBe(1);
    expect(notify).toHaveBeenCalledWith(copy.week.copiedLastWeek.text);
  });

  it("says when last week has nothing to copy", async () => {
    const { notify, writes } = await setup();
    expect(await writes.copyLastWeek(THIS)).toBe(true);
    expect(notify).toHaveBeenCalledWith(copy.week.nothingToCopy.text);
  });

  it("clears the week at once, and puts it back when the API refuses", async () => {
    const meals = [entry(1, "2026-09-29"), entry(2, "2026-09-30")];
    const { server, notify, writes, week, settled } = await setup({ entries: meals });

    server.failNext("clear", new InvalidRequest({ message: "No." }));
    const release = server.pause();
    const clearing = writes.clear(THIS);
    await vi.waitFor(() => expect(week(THIS)).toEqual([]));
    release();
    expect(await clearing).toBe(false);
    expect(week(THIS)).toEqual(meals);
    expect(notify).toHaveBeenCalledWith(copy.week.couldntSave.text, "error");

    expect(await writes.clear(THIS)).toBe(true);
    await settled();
    expect(week(THIS)).toEqual([]);
    expect(server.entries()).toEqual([]);
    expect(notify).toHaveBeenCalledWith(copy.week.cleared.text);
  });

  it("stirs a recipe in at once, and only once when the answer is lost and it retries", async () => {
    const { server, writes, week, settled } = await setup({ recipes: [stew] });
    // The first add lands, but the connection drops before the answer arrives.
    server.failNext("add", new TypeError("Failed to fetch"), { landed: true });

    const release = server.pause();
    const stirring = writes.stir({ date: "2026-09-30", slot: "dinner", recipeId: stew.id }, stew);
    await vi.waitFor(() => expect(week(THIS)).toHaveLength(1));
    expect(isPending(week(THIS)![0]!)).toBe(true);
    release();

    expect(await stirring).toBe(true);
    expect(server.calls.add).toBe(2);
    expect(server.entries()).toHaveLength(1);
    await settled();
    expect(week(THIS)).toHaveLength(1);
    expect(week(THIS)![0]).toMatchObject({ title: "Stew", recipe: stew });
  });
});
