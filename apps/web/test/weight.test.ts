import { trendSeries } from "@cauldron/shared";
import { describe, expect, it } from "vite-plus/test";
import {
  averageIntake,
  buildChart,
  niceTicks,
  parseWeight,
  signedChange,
  weightLimits,
} from "../src/lib/weight.ts";

describe("parseWeight", () => {
  it("reads kilograms and pounds", () => {
    expect(parseWeight("72.4", "kg")).toBeCloseTo(72.4);
    expect(parseWeight("160", "lb")).toBeCloseTo(72.575, 2);
    expect(parseWeight("72,4", "kg")).toBeCloseTo(72.4);
  });
  it("refuses empty, non-numbers and out of range", () => {
    expect(parseWeight("", "kg")).toBeNull();
    expect(parseWeight("abc", "kg")).toBeNull();
    expect(parseWeight("19", "kg")).toBeNull();
    expect(parseWeight("401", "kg")).toBeNull();
    expect(parseWeight("43", "lb")).toBeNull();
  });
  it("accepts the limits in either unit", () => {
    for (const unit of ["kg", "lb"] as const) {
      const { min, max } = weightLimits(unit);
      expect(parseWeight(String(min), unit)).not.toBeNull();
      expect(parseWeight(String(max), unit)).not.toBeNull();
    }
  });
});

describe("signedChange", () => {
  it("signs and rounds to one decimal", () => {
    expect(signedChange(0.44, "kg")).toBe("+0.4");
    expect(signedChange(-1.234, "kg")).toBe("−1.2");
    expect(signedChange(0.01, "kg")).toBe("0.0");
    expect(signedChange(-1, "lb")).toBe("−2.2");
  });
});

describe("niceTicks", () => {
  it("covers the range with round steps", () => {
    const ticks = niceTicks(71.3, 74.8);
    expect(ticks[0]!).toBeLessThanOrEqual(71.3);
    expect(ticks[ticks.length - 1]!).toBeGreaterThanOrEqual(74.8);
    expect(ticks.length).toBeGreaterThanOrEqual(3);
  });
  it("widens a flat range", () => expect(niceTicks(70, 70)).toEqual([69, 70, 71]));
});

describe("buildChart", () => {
  const points = trendSeries([
    { date: "2026-09-01", weightKg: 80 },
    { date: "2026-09-15", weightKg: 79 },
    { date: "2026-10-01", weightKg: 78 },
  ] as never);
  const chart = buildChart(points, "kg", "2026-09-01", "2026-10-01");

  it("spans the x axis from start to end", () => {
    expect(chart.dots[0]!.x).toBeCloseTo(chart.plot.left);
    expect(chart.dots[2]!.x).toBeCloseTo(chart.plot.right);
    expect(chart.xTicks[0]!.date).toBe("2026-09-01");
    expect(chart.xTicks[chart.xTicks.length - 1]!.date).toBe("2026-10-01");
  });
  it("puts heavier weights higher up", () => {
    expect(chart.dots[0]!.y).toBeLessThan(chart.dots[2]!.y);
    expect(chart.dots.every((d) => d.y >= chart.plot.top && d.y <= chart.plot.bottom)).toBe(true);
  });
  it("draws the trend as one path, and nothing without points", () => {
    expect(chart.line.startsWith("M")).toBe(true);
    expect(chart.line.match(/L/g)).toHaveLength(2);
    expect(buildChart([], "kg", "2026-09-01", "2026-10-01").line).toBe("");
  });
  it("copes with a single weigh-in on the start day", () => {
    const one = buildChart(points.slice(0, 1), "kg", "2026-09-01", "2026-09-01");
    expect(Number.isFinite(one.dots[0]!.x)).toBe(true);
  });
});

describe("averageIntake", () => {
  const day = (calories: number, protein: number) => ({
    date: "2026-10-01",
    entries: 2,
    totals: { calories, protein, carbs: 100, fat: 50 },
  });
  it("averages over logged days", () => {
    const avg = averageIntake([day(2000, 100), day(1000, 50)] as never);
    expect(avg).toMatchObject({ days: 2, calories: 1500, protein: 75, carbs: 100, fat: 50 });
  });
  it("is null with nothing logged", () => expect(averageIntake([])).toBeNull());
});
