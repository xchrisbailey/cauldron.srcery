import { noMacros, type PlanEntry, type PlanEntryInput, type RecipeId } from "@cauldron/shared";
import { describe, expect, it } from "vite-plus/test";
import {
  applyAdd,
  applyRemove,
  applyUpdate,
  dropAt,
  dropMove,
  inSlot,
  isPending,
  pendingEntry,
} from "../src/lib/plan.ts";

type Slot = PlanEntry["slot"];

const entry = (
  id: string,
  date: string,
  slot: Slot,
  position: number,
  extra: Partial<PlanEntry> = {},
): PlanEntry => ({
  id: id as PlanEntry["id"],
  date,
  slot,
  title: `title-${id}`,
  recipe: null,
  servings: null,
  position,
  brewed: false,
  ...extra,
});

/** [id, date, slot, position] for compact assertions. */
const shape = (entries: ReadonlyArray<PlanEntry>) =>
  entries.map((e) => [e.id, e.date, e.slot, e.position]);

const D1 = "2026-10-05";
const D2 = "2026-10-06";

describe("inSlot", () => {
  const entries = [
    entry("c", D1, "dinner", 2),
    entry("a", D1, "dinner", 0),
    entry("b", D1, "dinner", 1),
    entry("x", D1, "lunch", 0),
    entry("y", D2, "dinner", 0),
  ];

  it("filters to the day and slot, ordered by position", () => {
    expect(inSlot(entries, D1, "dinner").map((e) => e.id)).toEqual(["a", "b", "c"]);
  });

  it("is empty for an empty slot", () => {
    expect(inSlot(entries, D1, "snack")).toEqual([]);
    expect(inSlot([], D1, "dinner")).toEqual([]);
  });

  it("does not mutate its input", () => {
    const before = entries.map((e) => e.id);
    inSlot(entries, D1, "dinner");
    expect(entries.map((e) => e.id)).toEqual(before);
  });
});

describe("applyUpdate", () => {
  const week = [
    entry("l", D1, "lunch", 0),
    entry("a", D1, "dinner", 0),
    entry("b", D1, "dinner", 1),
    entry("c", D1, "dinner", 2),
    entry("m", D2, "dinner", 0),
    entry("n", D2, "dinner", 1),
  ];

  it("returns the same entries for an unknown id", () => {
    expect(applyUpdate(week, "nope", { slot: "lunch" })).toBe(week);
  });

  it("servings-only updates change just that entry and keep order", () => {
    const out = applyUpdate(week, "b", { servings: 6 });
    expect(out.find((e) => e.id === "b")!.servings).toBe(6);
    expect(shape(out)).toEqual(shape(week));
  });

  it("servings can be reset to null", () => {
    const out = applyUpdate([entry("a", D1, "dinner", 0, { servings: 4 })], "a", {
      servings: null,
    });
    expect(out[0]!.servings).toBeNull();
  });

  it("title-only updates rename without reordering", () => {
    const out = applyUpdate(week, "c", { title: "Leftovers" });
    expect(out.find((e) => e.id === "c")!.title).toBe("Leftovers");
    expect(shape(out)).toEqual(shape(week));
  });

  it("does not mutate its input", () => {
    const snapshot = JSON.stringify(week);
    applyUpdate(week, "a", { slot: "lunch", position: 0 });
    expect(JSON.stringify(week)).toBe(snapshot);
  });

  describe("moving to another slot", () => {
    it("lands at the end by default and renumbers the old slot", () => {
      const out = applyUpdate(week, "a", { slot: "lunch" });
      expect(inSlot(out, D1, "lunch").map((e) => [e.id, e.position])).toEqual([
        ["l", 0],
        ["a", 1],
      ]);
      expect(inSlot(out, D1, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["b", 0],
        ["c", 1],
      ]);
    });

    it("lands at the given position and renumbers the target densely", () => {
      const out = applyUpdate(week, "a", { slot: "lunch", position: 0 });
      expect(inSlot(out, D1, "lunch").map((e) => [e.id, e.position])).toEqual([
        ["a", 0],
        ["l", 1],
      ]);
    });

    it("clamps an out-of-range position to the end", () => {
      const out = applyUpdate(week, "a", { slot: "lunch", position: 99 });
      expect(inSlot(out, D1, "lunch").map((e) => e.id)).toEqual(["l", "a"]);
      expect(inSlot(out, D1, "lunch").map((e) => e.position)).toEqual([0, 1]);
    });

    it("moves to another day, keeping the slot", () => {
      const out = applyUpdate(week, "c", { date: D2 });
      expect(inSlot(out, D2, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["m", 0],
        ["n", 1],
        ["c", 2],
      ]);
      expect(inSlot(out, D1, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["a", 0],
        ["b", 1],
      ]);
    });

    it("moves to another day and slot at once, into an empty slot", () => {
      const out = applyUpdate(week, "m", { date: D1, slot: "snack" });
      expect(inSlot(out, D1, "snack").map((e) => [e.id, e.position])).toEqual([["m", 0]]);
      expect(inSlot(out, D2, "dinner").map((e) => [e.id, e.position])).toEqual([["n", 0]]);
    });

    it("renumbers a sparse source slot densely", () => {
      const sparse = [
        entry("a", D1, "dinner", 0),
        entry("b", D1, "dinner", 5),
        entry("c", D1, "dinner", 9),
      ];
      const out = applyUpdate(sparse, "a", { slot: "lunch" });
      expect(inSlot(out, D1, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["b", 0],
        ["c", 1],
      ]);
    });

    it("leaves other slots untouched", () => {
      const out = applyUpdate(week, "a", { slot: "lunch" });
      expect(inSlot(out, D2, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["m", 0],
        ["n", 1],
      ]);
    });

    it("applies servings alongside a move", () => {
      const out = applyUpdate(week, "a", { slot: "lunch", servings: 3 });
      const a = out.find((e) => e.id === "a")!;
      expect(a.servings).toBe(3);
      expect(a.slot).toBe("lunch");
    });
  });

  describe("reordering within a slot", () => {
    it("moves an entry earlier", () => {
      const out = applyUpdate(week, "c", { position: 0 });
      expect(inSlot(out, D1, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["c", 0],
        ["a", 1],
        ["b", 2],
      ]);
    });

    it("moves an entry later", () => {
      const out = applyUpdate(week, "a", { position: 2 });
      expect(inSlot(out, D1, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["b", 0],
        ["c", 1],
        ["a", 2],
      ]);
    });

    it("inserts among siblings excluding the moved entry", () => {
      const out = applyUpdate(week, "a", { position: 1 });
      expect(inSlot(out, D1, "dinner").map((e) => e.id)).toEqual(["b", "a", "c"]);
    });

    it("clamps a position past the end", () => {
      const out = applyUpdate(week, "a", { position: 50 });
      expect(inSlot(out, D1, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["b", 0],
        ["c", 1],
        ["a", 2],
      ]);
    });

    it("keeps order when position equals the current position", () => {
      const out = applyUpdate(week, "b", { position: 1 });
      expect(shape(out)).toEqual(shape(week));
    });

    it("does not touch other slots", () => {
      const out = applyUpdate(week, "c", { position: 0 });
      expect(inSlot(out, D1, "lunch").map((e) => [e.id, e.position])).toEqual([["l", 0]]);
      expect(inSlot(out, D2, "dinner").map((e) => [e.id, e.position])).toEqual([
        ["m", 0],
        ["n", 1],
      ]);
    });

    it("treats a date/slot equal to the current one as a reorder, not a move", () => {
      const out = applyUpdate(week, "a", { date: D1, slot: "dinner", position: 1 });
      expect(inSlot(out, D1, "dinner").map((e) => e.id)).toEqual(["b", "a", "c"]);
    });

    it("keeps the current place for a same-slot update without a position", () => {
      const out = applyUpdate(week, "b", { slot: "dinner" });
      expect(inSlot(out, D1, "dinner").map((e) => e.id)).toEqual(["a", "b", "c"]);
    });
  });

  describe("result ordering", () => {
    it("sorts by date, then meal slot, then position", () => {
      const unsorted = [
        entry("s", D2, "snack", 0),
        entry("d", D1, "dinner", 0),
        entry("b", D1, "breakfast", 0),
        entry("l", D1, "lunch", 0),
        entry("k", D1, "snack", 0),
        entry("b2", D2, "breakfast", 0),
      ];
      const out = applyUpdate(unsorted, "l", { position: 0 });
      expect(out.map((e) => e.id)).toEqual(["b", "l", "d", "k", "b2", "s"]);
    });

    it("sorts a moved entry into its new slot's place", () => {
      const out = applyUpdate(week, "m", { date: D1, slot: "breakfast" });
      expect(out[0]).toMatchObject({ id: "m", date: D1, slot: "breakfast", position: 0 });
    });
  });
});

describe("applyRemove", () => {
  const week = [
    entry("a", D1, "dinner", 0),
    entry("b", D1, "dinner", 1),
    entry("c", D1, "dinner", 2),
    entry("l", D1, "lunch", 0),
  ];

  it("returns the same entries for an unknown id", () => {
    expect(applyRemove(week, "nope")).toBe(week);
  });

  it("drops the entry and renumbers its slot densely", () => {
    const out = applyRemove(week, "a");
    expect(out.find((e) => e.id === "a")).toBeUndefined();
    expect(inSlot(out, D1, "dinner").map((e) => [e.id, e.position])).toEqual([
      ["b", 0],
      ["c", 1],
    ]);
  });

  it("removes from the middle", () => {
    const out = applyRemove(week, "b");
    expect(inSlot(out, D1, "dinner").map((e) => [e.id, e.position])).toEqual([
      ["a", 0],
      ["c", 1],
    ]);
  });

  it("leaves other slots alone", () => {
    const out = applyRemove(week, "a");
    expect(inSlot(out, D1, "lunch").map((e) => [e.id, e.position])).toEqual([["l", 0]]);
  });

  it("removing the only entry leaves an empty slot", () => {
    const out = applyRemove(week, "l");
    expect(out.map((e) => e.id)).toEqual(["a", "b", "c"]);
  });

  it("closes gaps in a sparse slot", () => {
    const out = applyRemove(
      [entry("a", D1, "dinner", 0), entry("b", D1, "dinner", 4), entry("c", D1, "dinner", 8)],
      "a",
    );
    expect(out.map((e) => e.position)).toEqual([0, 1]);
  });

  it("does not mutate its input", () => {
    const snapshot = JSON.stringify(week);
    applyRemove(week, "a");
    expect(JSON.stringify(week)).toBe(snapshot);
  });
});

describe("pendingEntry / isPending", () => {
  const recipe = {
    id: "r1" as RecipeId,
    title: "Chili",
    servings: 4,
    totalMinutes: 90,
    photoKey: "photo-1",
    macros: noMacros,
  };

  it("builds a placeholder for a recipe entry from the recipe, photo and all", () => {
    const input: PlanEntryInput = { date: D1, slot: "dinner", recipeId: "r1" as never };
    const e = pendingEntry(input, recipe, 2);
    expect(e).toMatchObject({
      date: D1,
      slot: "dinner",
      title: "Chili",
      servings: null,
      position: 2,
      brewed: false,
      recipe: { id: "r1", title: "Chili", servings: 4, totalMinutes: 90, photoKey: "photo-1" },
    });
    expect(isPending(e)).toBe(true);
  });

  it("uses the input's servings when given", () => {
    const e = pendingEntry({ date: D1, slot: "lunch", servings: 6 }, recipe, 0);
    expect(e.servings).toBe(6);
  });

  it("builds a free-text placeholder with no recipe", () => {
    const e = pendingEntry({ date: D1, slot: "snack", title: "Fruit" }, null, 0);
    expect(e.title).toBe("Fruit");
    expect(e.recipe).toBeNull();
    expect(isPending(e)).toBe(true);
  });

  it("falls back to an empty title with neither recipe nor text", () => {
    expect(pendingEntry({ date: D1, slot: "snack" }, null, 0).title).toBe("");
  });

  it("gives each placeholder a distinct id", () => {
    const a = pendingEntry({ date: D1, slot: "snack", title: "x" }, null, 0);
    const b = pendingEntry({ date: D1, slot: "snack", title: "x" }, null, 0);
    expect(a.id).not.toBe(b.id);
  });

  it("does not flag real entries as pending", () => {
    expect(isPending(entry("abc", D1, "dinner", 0))).toBe(false);
  });
});

describe("applyAdd", () => {
  const entries = [entry("a", D1, "dinner", 0), entry("b", D1, "dinner", 1)];

  it("inserts at the entry's position and renumbers the slot", () => {
    expect(shape(applyAdd(entries, entry("n", D1, "dinner", 1)))).toEqual([
      ["a", D1, "dinner", 0],
      ["n", D1, "dinner", 1],
      ["b", D1, "dinner", 2],
    ]);
  });

  it("clamps a position past the end", () => {
    expect(shape(applyAdd(entries, entry("n", D1, "dinner", 9))).at(-1)).toEqual([
      "n",
      D1,
      "dinner",
      2,
    ]);
  });
});

describe("dropMove", () => {
  const entries = [
    entry("a", D1, "dinner", 0),
    entry("b", D1, "dinner", 1),
    entry("c", D1, "dinner", 2),
    entry("x", D2, "lunch", 0),
  ];
  const dinner = { date: D1, slot: "dinner" as const };

  it("does nothing when a meal is dropped on itself", () => {
    expect(dropMove(entries, "b", dinner, "b")).toBeNull();
  });

  it("does nothing when a meal is dropped back where it was", () => {
    // The last meal dropped on its own slot's empty space stays last.
    expect(dropMove(entries, "c", dinner)).toBeNull();
    // Dropped on the meal right after it: that's where it already is.
    expect(dropMove(entries, "a", dinner, "b")).toBeNull();
  });

  it("moves before the meal it was dropped on", () => {
    expect(dropMove(entries, "c", dinner, "a")).toEqual({ ...dinner, position: 0 });
  });

  it("moves to the end of the slot when dropped on empty space", () => {
    expect(dropMove(entries, "a", dinner)).toEqual({ ...dinner, position: 2 });
    expect(dropMove(entries, "a", { date: D2, slot: "lunch" })).toEqual({
      date: D2,
      slot: "lunch",
      position: 1,
    });
  });

  it("ignores an unknown meal", () => {
    expect(dropMove(entries, "nope", dinner)).toBeNull();
  });
});

describe("dropAt", () => {
  const entries = [entry("a", D1, "dinner", 0), entry("b", D1, "dinner", 1)];

  it("places a dropped recipe before the meal it landed on, or at the end", () => {
    expect(dropAt(entries, { date: D1, slot: "dinner" }, "b")).toBe(1);
    expect(dropAt(entries, { date: D1, slot: "dinner" })).toBeUndefined();
    expect(dropAt(entries, { date: D1, slot: "dinner" }, "gone")).toBeUndefined();
  });
});
