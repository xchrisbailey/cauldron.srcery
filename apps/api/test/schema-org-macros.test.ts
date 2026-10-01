import { describe, expect, it } from "vite-plus/test";
import { macrosOf } from "../src/imports/schemaOrg.ts";

describe("macrosOf", () => {
  it("reads schema.org NutritionInformation per serving", () => {
    expect(
      macrosOf({
        "@type": "NutritionInformation",
        calories: "1,250 kcal",
        proteinContent: "31.5 g",
        carbohydrateContent: "12,5 g",
        fatContent: 18,
      }),
    ).toEqual({ calories: 1250, protein: 31.5, carbs: 12.5, fat: 18 });
  });

  it("leaves what's missing unknown", () => {
    expect(macrosOf({ calories: "240 calories" })).toEqual({
      calories: 240,
      protein: null,
      carbs: null,
      fat: null,
    });
  });

  it("returns nothing when there's nothing to read", () => {
    expect(macrosOf(undefined)).toBeUndefined();
    expect(macrosOf({ servingSize: "1 bowl" })).toBeUndefined();
    expect(macrosOf("lots")).toBeUndefined();
  });
});
