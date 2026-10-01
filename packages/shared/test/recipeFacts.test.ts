import { describe, expect, it } from "vite-plus/test";
import {
  noMacros,
  RECIPE_LIMITS,
  RecipeId,
  recipeMinutes,
  SCALE_MULTIPLIERS,
  Scale,
  servingFactor,
  toPlanRecipe,
} from "../src/index.ts";

describe("recipeMinutes", () => {
  it.each([
    { total: 45, prep: 10, cook: 20, minutes: 45 },
    { total: null, prep: 10, cook: 20, minutes: 30 },
    { total: null, prep: 10, cook: null, minutes: 10 },
    { total: null, prep: null, cook: 20, minutes: 20 },
    { total: null, prep: null, cook: null, minutes: null },
    { total: 0, prep: 10, cook: 20, minutes: 0 },
  ])("total $total, prep $prep, cook $cook → $minutes", ({ total, prep, cook, minutes }) => {
    expect(recipeMinutes({ totalMinutes: total, prepMinutes: prep, cookMinutes: cook })).toBe(
      minutes,
    );
  });
});

describe("servingFactor", () => {
  it.each([
    { recipe: 4, wanted: 8, factor: 2 },
    { recipe: 4, wanted: 2, factor: 0.5 },
    { recipe: 4, wanted: 4, factor: 1 },
    { recipe: null, wanted: 8, factor: 1 },
    { recipe: 4, wanted: null, factor: 1 },
    { recipe: null, wanted: null, factor: 1 },
  ])("$wanted of $recipe → $factor", ({ recipe, wanted, factor }) => {
    expect(servingFactor(recipe, wanted)).toBe(factor);
  });
});

describe("toPlanRecipe", () => {
  it("carries the photo and works out the minutes", () => {
    const id = RecipeId.make("6f1d7c1e-9a3b-4c55-8e0a-2b8f7f5d9a10");
    expect(
      toPlanRecipe({
        id,
        title: "Soup",
        servings: 4,
        totalMinutes: null,
        prepMinutes: 5,
        cookMinutes: 25,
        photoKey: "photo-1",
        macros: noMacros,
      }),
    ).toEqual({
      id,
      title: "Soup",
      servings: 4,
      totalMinutes: 30,
      photoKey: "photo-1",
      macros: noMacros,
    });
  });
});

const servings = (n: number): Scale => ({ by: "servings", servings: n });
const multiplier = (m: number): Scale => ({ by: "multiplier", multiplier: m });

describe("Scale", () => {
  it("starts at the recipe's servings, or unscaled", () => {
    expect(Scale.initialScale({ servings: 4 })).toEqual(servings(4));
    expect(Scale.initialScale({ servings: null })).toEqual(multiplier(1));
  });

  it.each([
    { scale: servings(4), recipe: 2, factor: 2 },
    { scale: servings(4), recipe: null, factor: 1 },
    { scale: multiplier(1.5), recipe: 2, factor: 1.5 },
    { scale: multiplier(0.25), recipe: null, factor: 0.25 },
  ])("factor of $scale for $recipe servings → $factor", ({ scale, recipe, factor }) => {
    expect(Scale.factor(scale, recipe)).toBe(factor);
  });

  it.each([
    { scale: servings(1), direction: -1, can: false, to: servings(1) },
    { scale: servings(1), direction: 1, can: true, to: servings(2) },
    { scale: servings(2), direction: -1, can: true, to: servings(1) },
    {
      scale: servings(RECIPE_LIMITS.servings),
      direction: 1,
      can: false,
      to: servings(RECIPE_LIMITS.servings),
    },
    {
      scale: servings(RECIPE_LIMITS.servings - 1),
      direction: 1,
      can: true,
      to: servings(RECIPE_LIMITS.servings),
    },
  ] as const)("servings bounds: $scale by $direction", ({ scale, direction, can, to }) => {
    expect(Scale.canStep(scale, direction)).toBe(can);
    expect(Scale.step(scale, direction)).toEqual(to);
  });

  it("climbs and descends the multiplier ladder one rung at a time", () => {
    const up: Array<number> = [];
    for (let s = multiplier(SCALE_MULTIPLIERS[0]); ; s = Scale.step(s, 1)) {
      up.push((s as { multiplier: number }).multiplier);
      if (!Scale.canStep(s, 1)) break;
    }
    expect(up).toEqual([0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 8]);

    const down: Array<number> = [];
    for (let s = multiplier(8); ; s = Scale.step(s, -1)) {
      down.push((s as { multiplier: number }).multiplier);
      if (!Scale.canStep(s, -1)) break;
    }
    expect(down).toEqual([...up].reverse());
  });

  it.each([
    { scale: multiplier(0.25), direction: -1, can: false, to: multiplier(0.25) },
    { scale: multiplier(8), direction: 1, can: false, to: multiplier(8) },
    { scale: multiplier(1), direction: 1, can: true, to: multiplier(1.5) },
    { scale: multiplier(1), direction: -1, can: true, to: multiplier(0.5) },
  ] as const)("multiplier bounds: $scale by $direction", ({ scale, direction, can, to }) => {
    expect(Scale.canStep(scale, direction)).toBe(can);
    expect(Scale.step(scale, direction)).toEqual(to);
  });

  it.each([
    servings(1),
    servings(6),
    servings(RECIPE_LIMITS.servings),
    ...SCALE_MULTIPLIERS.map(multiplier),
  ])("round trips $scale through search params", (scale) => {
    expect(Scale.fromSearch(Scale.toSearch(scale))).toEqual(scale);
  });

  it("leaves an unscaled recipe out of the URL", () => {
    expect(Scale.toSearch(multiplier(1))).toEqual({});
  });

  it.each([
    { search: {}, scale: multiplier(1) },
    { search: { servings: "6" }, scale: servings(6) },
    { search: { multiplier: "1.5" }, scale: multiplier(1.5) },
    { search: { servings: 0 }, scale: multiplier(1) },
    { search: { servings: RECIPE_LIMITS.servings + 1 }, scale: multiplier(1) },
    { search: { servings: 2.5 }, scale: multiplier(1) },
    { search: { servings: "" }, scale: multiplier(1) },
    { search: { servings: true }, scale: multiplier(1) },
    { search: { multiplier: 2.5 }, scale: multiplier(1) },
    { search: { multiplier: 100 }, scale: multiplier(1) },
    { search: { multiplier: -1 }, scale: multiplier(1) },
    { search: { servings: 4, multiplier: 2 }, scale: servings(4) },
  ])("reads $search as $scale", ({ search, scale }) => {
    expect(Scale.fromSearch(search)).toEqual(scale);
  });
});
