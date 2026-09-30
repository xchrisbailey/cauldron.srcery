import { describe, expect, it } from "vite-plus/test";
import { ingredientKey } from "../../src/index.ts";

describe("ingredientKey", () => {
  it.each([
    ["Eggs", "egg"],
    ["large eggs", "egg"],
    ["  Large   Eggs ", "egg"],
    ["medium onions", "onion"],
    ["small red onion", "red onion"],
    ["tomatoes", "tomato"],
    ["potatoes", "potato"],
    ["cherries", "cherry"],
    ["berries", "berry"],
    ["peaches", "peach"],
    ["radishes", "radish"],
    ["cloves", "clove"],
    ["olives", "olive"],
    ["bay leaves", "bay leaf"],
    ["chickpeas", "chickpea"],
    ["hummus", "hummus"],
    ["asparagus", "asparagus"],
    ["couscous", "couscous"],
    ["molasses", "molasses"],
    ["olive oil", "olive oil"],
    ["Olive Oil", "olive oil"],
    ["green onions", "green onion"],
    ["extra large egg yolks", "egg yolk"],
    ["", ""],
  ])("%s -> %s", (input, expected) => {
    expect(ingredientKey(input)).toBe(expected);
  });

  it("is idempotent", () => {
    for (const s of ["Large Eggs", "tomatoes", "bay leaves", "cherries"]) {
      expect(ingredientKey(ingredientKey(s))).toBe(ingredientKey(s));
    }
  });
});
