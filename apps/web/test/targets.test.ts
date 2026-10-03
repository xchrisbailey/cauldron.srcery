import { TRACKER_LIMITS, WeighInInput } from "@cauldron/shared";
import { describe, expect, it } from "vite-plus/test";
import {
  defaultRate,
  firstIssue,
  heightToCm,
  nearestRate,
  parseNumber,
  rateChoices,
  resolveTargets,
} from "../src/lib/targets.ts";

describe("parseNumber", () => {
  it.each([
    ["70", 70],
    [" 70,5 ", 70.5],
    ["", null],
    ["abc", null],
  ])("%j -> %j", (text, expected) => expect(parseNumber(text)).toBe(expected));
});

describe("heightToCm", () => {
  it("reads centimetres", () =>
    expect(heightToCm("cm", { cm: "172", feet: "", inches: "" })).toBe(172));
  it("reads feet and inches, with inches optional", () => {
    expect(heightToCm("ftin", { cm: "", feet: "5", inches: "10" })).toBeCloseTo(177.8);
    expect(heightToCm("ftin", { cm: "", feet: "6", inches: "" })).toBeCloseTo(182.88);
    expect(heightToCm("ftin", { cm: "", feet: "", inches: "3" })).toBeNull();
  });
});

describe("rate choices", () => {
  it("offers none when maintaining", () => expect(rateChoices("maintain", "kg")).toEqual([]));
  it("caps losing at 1 kg and gaining at 0.5 kg a week", () => {
    expect(Math.max(...rateChoices("lose", "kg").map((c) => c.kg))).toBe(1);
    expect(Math.max(...rateChoices("gain", "kg").map((c) => c.kg))).toBe(0.5);
    expect(Math.max(...rateChoices("lose", "lb").map((c) => c.kg))).toBeLessThanOrEqual(1);
    expect(Math.max(...rateChoices("gain", "lb").map((c) => c.kg))).toBeLessThanOrEqual(0.5);
  });
  it("defaults to half a kilo or a pound", () => {
    expect(defaultRate("lose", "kg")).toBe(0.5);
    expect(defaultRate("gain", "lb")).toBe(1);
    expect(defaultRate("maintain", "kg")).toBeNull();
  });
  it("finds the nearest choice to a stored rate", () => {
    expect(nearestRate("lose", "kg", 0.45)).toBe(0.5);
    expect(nearestRate("lose", "lb", 0.45)).toBe(1);
  });
});

describe("resolveTargets", () => {
  const calculated = { calories: 2000, protein: 126, carbs: 230, fat: 56 };
  const base = { calculated, weightKg: 70, proteinPerKg: 1.8, fatShare: 0.25 };

  it("keeps the calculated numbers when nothing is overridden", () => {
    const r = resolveTargets({ ...base, overrides: {} });
    expect(r.values).toEqual(calculated);
    expect(Object.values(r.overridden)).toEqual([false, false, false, false]);
  });

  it("re-splits the macros that weren't set when calories change", () => {
    const r = resolveTargets({ ...base, overrides: { calories: "2400" } });
    expect(r.values.calories).toBe(2400);
    expect(r.values.protein).toBe(126);
    expect(r.values.carbs).toBeGreaterThan(calculated.carbs);
    expect(r.overridden).toEqual({ calories: true, protein: false, carbs: false, fat: false });
  });

  it("leaves a macro the cook set alone when calories change", () => {
    const r = resolveTargets({ ...base, overrides: { calories: "2400", fat: "80" } });
    expect(r.values.fat).toBe(80);
    expect(r.overridden.fat).toBe(true);
  });

  it("falls back to the calculated value while an override isn't a number", () => {
    const r = resolveTargets({ ...base, overrides: { protein: "" } });
    expect(r.values.protein).toBe(126);
    expect(r.overridden.protein).toBe(true);
  });
});

describe("firstIssue", () => {
  it("returns the schema's plain message, or nothing", () => {
    expect(firstIssue(WeighInInput, { weightKg: 70 })).toBeUndefined();
    expect(firstIssue(WeighInInput, { weightKg: TRACKER_LIMITS.weightKg.max + 1 })).toMatch(
      /Use a number from/,
    );
  });
});
