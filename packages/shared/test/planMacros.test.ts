import { describe, expect, it } from "vite-plus/test";
import {
  hasMacros,
  type Macros,
  noMacros,
  oneADay,
  type PlanEntry,
  type PlanEntryId,
  type RecipeId,
  tallyMacros,
} from "../src/index.ts";

const recipe = (macros: Macros) =>
  ({
    id: "8f0c2a4e-1b6d-4c1e-9a53-0d2f6b7a9c11" as RecipeId,
    title: "Chili",
    servings: 5,
    totalMinutes: 60,
    photoKey: null,
    macros,
  }) as const;

const entry = (patch: Partial<PlanEntry>): PlanEntry => ({
  id: crypto.randomUUID() as PlanEntryId,
  date: "2026-10-05",
  slot: "dinner",
  title: "Chili",
  recipe: recipe({ calories: 500, protein: 30, carbs: 40, fat: 20 }),
  servings: 1,
  position: 0,
  brewed: false,
  ...patch,
});

describe("tallyMacros", () => {
  it("multiplies per-serving macros by the servings planned", () => {
    const tally = tallyMacros([entry({ servings: 2 }), entry({ servings: 1 })]);
    expect(tally.totals).toEqual({ calories: 1500, protein: 90, carbs: 120, fat: 60 });
    expect(tally.counted).toBe(2);
    expect(tally.missing).toBe(0);
  });

  it("uses the recipe's servings when the entry follows the recipe", () => {
    expect(tallyMacros([entry({ servings: null })]).totals.calories).toBe(2500);
  });

  it("adds what a partial recipe has and reports it as missing", () => {
    const tally = tallyMacros([
      entry({}),
      entry({ recipe: recipe({ calories: 300, protein: null, carbs: null, fat: null }) }),
      entry({ recipe: recipe(noMacros) }),
    ]);
    expect(tally.totals.calories).toBe(800);
    expect(tally.totals.protein).toBe(30);
    expect(tally.counted).toBe(1);
    expect(tally.missing).toBe(2);
  });

  it("leaves free-text meals out of the totals and the gaps", () => {
    const tally = tallyMacros([entry({ recipe: null, title: "Leftovers" })]);
    expect(tally.freeText).toBe(1);
    expect(tally.missing).toBe(0);
    expect(hasMacros(tally)).toBe(false);
  });
});

describe("oneADay", () => {
  const days = ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"];

  it("gives one serving a day from the start day until the servings run out", () => {
    expect([...oneADay(days, "2026-10-06", 3)]).toEqual([
      ["2026-10-06", 1],
      ["2026-10-07", 1],
      ["2026-10-08", 1],
    ]);
  });

  it("stops at the end of the week", () => {
    expect([...oneADay(days, "2026-10-08", 5)].map(([d]) => d)).toEqual([
      "2026-10-08",
      "2026-10-09",
    ]);
  });

  it("is just the start day when the recipe's servings are unknown", () => {
    expect([...oneADay(days, "2026-10-05", null)]).toEqual([["2026-10-05", 1]]);
  });
});
