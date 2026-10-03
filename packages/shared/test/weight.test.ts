import { describe, expect, it } from "vite-plus/test";
import {
  addDays,
  cmToFeetInches,
  feetInchesToCm,
  fromKg,
  KG_PER_LB,
  rangeStart,
  roundWeight,
  toKg,
  TREND_SMOOTHING,
  trendChange,
  trendOn,
  trendSeries,
  type WeighIn,
} from "../src/index.ts";

const w = (date: string, weightKg: number): WeighIn => ({ date, weightKg });

describe("units", () => {
  it("round trips kg and lb", () => {
    expect(toKg(1, "lb")).toBeCloseTo(KG_PER_LB, 10);
    expect(toKg(80, "kg")).toBe(80);
    expect(fromKg(toKg(180, "lb"), "lb")).toBeCloseTo(180, 10);
    expect(roundWeight(fromKg(80, "lb"))).toBe(176.4);
  });

  it("rounds to one decimal", () => {
    expect(roundWeight(72.449)).toBe(72.4);
    expect(roundWeight(72.46)).toBe(72.5);
  });

  it("converts cm to feet and inches", () => {
    expect(cmToFeetInches(180)).toEqual({ feet: 5, inches: 10.9 });
    expect(cmToFeetInches(152.4)).toEqual({ feet: 5, inches: 0 });
  });

  it("carries 11.99 inches into the next foot", () => {
    expect(cmToFeetInches(feetInchesToCm(5, 11.99))).toEqual({ feet: 6, inches: 0 });
  });

  it("round trips ft/in through cm", () => {
    expect(feetInchesToCm(5, 10)).toBeCloseTo(177.8, 10);
    expect(cmToFeetInches(feetInchesToCm(5, 10))).toEqual({ feet: 5, inches: 10 });
  });
});

describe("trendSeries", () => {
  it("is empty for no weigh-ins", () => {
    expect(trendSeries([])).toEqual([]);
  });

  it("starts at the first weight", () => {
    expect(trendSeries([w("2026-10-01", 80)])).toEqual([
      { date: "2026-10-01", weightKg: 80, trendKg: 80 },
    ]);
  });

  it("converges toward a steady weight", () => {
    const weighIns = [
      w("2026-01-01", 90),
      ...Array.from({ length: 60 }, (_, i) => w(addDays("2026-01-02", i), 80)),
    ];
    const last = trendSeries(weighIns).at(-1)!;
    expect(last.trendKg).toBeGreaterThan(80);
    expect(last.trendKg).toBeLessThan(80.5);
  });

  it("moves a single spike by only alpha times the spike", () => {
    const series = trendSeries([w("2026-10-01", 80), w("2026-10-02", 80), w("2026-10-03", 85)]);
    expect(series[2]!.trendKg).toBeCloseTo(80 + TREND_SMOOTHING * 5, 10);
  });

  it("scales the step by the gap", () => {
    const series = trendSeries([w("2026-10-01", 80), w("2026-10-06", 85)]);
    expect(series[1]!.trendKg).toBeCloseTo(80 + (1 - 0.9 ** 5) * 5, 10);
  });

  it("keeps the last weigh-in for a duplicate day", () => {
    const series = trendSeries([w("2026-10-01", 80), w("2026-10-01", 82)]);
    expect(series).toEqual([{ date: "2026-10-01", weightKg: 82, trendKg: 82 }]);
  });

  it("sorts unsorted input", () => {
    const sorted = trendSeries([w("2026-10-01", 80), w("2026-10-02", 81), w("2026-10-04", 79)]);
    const shuffled = trendSeries([w("2026-10-04", 79), w("2026-10-01", 80), w("2026-10-02", 81)]);
    expect(shuffled).toEqual(sorted);
    expect(shuffled.map((p) => p.date)).toEqual(["2026-10-01", "2026-10-02", "2026-10-04"]);
  });
});

describe("trendOn and trendChange", () => {
  const series = trendSeries([w("2026-10-01", 80), w("2026-10-02", 81), w("2026-10-10", 79)]);

  it("uses the last point at or before the day", () => {
    expect(trendOn(series, "2026-09-30")).toBeNull();
    expect(trendOn(series, "2026-10-01")).toBe(80);
    expect(trendOn(series, "2026-10-05")).toBe(series[1]!.trendKg);
    expect(trendOn(series, "2026-12-01")).toBe(series[2]!.trendKg);
  });

  it("reports the change over a span", () => {
    expect(trendChange(series, 9, "2026-10-10")).toBeCloseTo(series[2]!.trendKg - 80, 10);
  });

  it("is null when either end is missing", () => {
    expect(trendChange(series, 30, "2026-10-10")).toBeNull();
    expect(trendChange(series, 7, "2026-09-20")).toBeNull();
    expect(trendChange([], 7, "2026-10-10")).toBeNull();
  });
});

describe("rangeStart", () => {
  it("counts back from today", () => {
    expect(rangeStart("1m", "2026-10-31")).toBe("2026-10-01");
    expect(rangeStart("3m", "2026-10-31")).toBe("2026-08-01");
    expect(rangeStart("1y", "2026-10-31")).toBe("2025-10-31");
    expect(rangeStart("all", "2026-10-31")).toBeNull();
  });
});
