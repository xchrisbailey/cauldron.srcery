import { describe, expect, it } from "vite-plus/test";
import {
  addDays,
  ADAPTIVE_LIMITS,
  estimateExpenditure,
  type IntakeCalories,
  type MacroTargets,
  proposeTargets,
  type TrendDay,
} from "../src/index.ts";

const today = "2026-10-21";
// The 21 day window is 2026-10-01 to 2026-10-21 inclusive.
const windowStart = addDays(today, -(ADAPTIVE_LIMITS.windowDays - 1));
const day = (i: number) => addDays(windowStart, i);

/** A simulated stretch: eat `intake` a day, burn `expenditure` a day, from `startKg`. */
const simulate = (opts: {
  readonly intake: number;
  readonly expenditure: number;
  readonly startKg?: number;
  readonly loggedDays?: ReadonlyArray<number>;
  readonly weighInDays?: ReadonlyArray<number>;
}) => {
  const all = Array.from({ length: ADAPTIVE_LIMITS.windowDays }, (_, i) => i);
  const kgPerDay = (opts.intake - opts.expenditure) / 7700;
  const startKg = opts.startKg ?? 80;
  const intake: IntakeCalories[] = (opts.loggedDays ?? all).map((i) => ({
    date: day(i),
    calories: opts.intake,
  }));
  const trend: TrendDay[] = (opts.weighInDays ?? all).map((i) => ({
    date: day(i),
    trendKg: startKg + kgPerDay * i,
  }));
  return { intake, trend };
};

const noOverrides = { calories: false, protein: false, carbs: false, fat: false };
const current: MacroTargets & { overridden: typeof noOverrides } = {
  calories: 2200,
  protein: 150,
  carbs: 250,
  fat: 70,
  overridden: noOverrides,
};

describe("estimateExpenditure", () => {
  it("measures a steady loss: eating 2000 while burning 2500", () => {
    const { intake, trend } = simulate({ intake: 2000, expenditure: 2500 });
    const estimate = estimateExpenditure({ intake, trend, today, calculatorExpenditure: 2800 });
    // Trend falls 500 / 7700 kg a day, about 0.45 kg a week
    expect((estimate.trendChangeKg! / 20) * 7).toBeCloseTo(-0.4545, 3);
    // measured = 2000 - (-20 * 500 / 7700 * 7700) / 20 = 2500
    expect(estimate.measured).toBeCloseTo(2500, 6);
    expect(estimate.confidence).toBe(1);
    expect(estimate.loggedDays).toBe(21);
    expect(estimate.weighIns).toBe(21);
    expect(estimate.expenditure).toBe(2500);
  });

  it("measures a plateau: eating 2400 with a flat trend", () => {
    const { intake, trend } = simulate({ intake: 2400, expenditure: 2400 });
    const estimate = estimateExpenditure({ intake, trend, today, calculatorExpenditure: 2600 });
    expect(estimate.measured).toBeCloseTo(2400, 6);
    expect(estimate.trendChangeKg).toBeCloseTo(0, 9);
    expect(estimate.expenditure).toBe(2400);
  });

  it("leans on the calculator when logging is sparse", () => {
    const { intake, trend } = simulate({
      intake: 2000,
      expenditure: 2500,
      loggedDays: [2, 8, 12, 19],
      weighInDays: [0, 10, 20],
    });
    const estimate = estimateExpenditure({ intake, trend, today, calculatorExpenditure: 2800 });
    // confidence = 4 / 14 * 3 / 10
    const confidence = (4 / 14) * (3 / 10);
    expect(estimate.confidence).toBeCloseTo(confidence, 9);
    expect(estimate.loggedDays).toBe(4);
    expect(estimate.weighIns).toBe(3);
    expect(estimate.measured).toBeCloseTo(2500, 6);
    // 0.0857 * 2500 + 0.9143 * 2800 = 2774.3 -> 2770
    expect(estimate.expenditure).toBe(2770);
    expect(Math.abs(estimate.expenditure - 2800)).toBeLessThan(50);
  });

  it("skips unlogged days instead of counting them as zero", () => {
    const full = simulate({ intake: 2000, expenditure: 2500 });
    const half = simulate({
      intake: 2000,
      expenditure: 2500,
      loggedDays: Array.from({ length: 21 }, (_, i) => i).filter((i) => i % 2 === 0),
    });
    const a = estimateExpenditure({ ...full, today, calculatorExpenditure: 2800 });
    const b = estimateExpenditure({ ...half, today, calculatorExpenditure: 2800 });
    expect(b.loggedDays).toBe(11);
    expect(b.measured).toBeCloseTo(a.measured!, 6);
    expect(b.measured).toBeCloseTo(2500, 6);
  });

  it("ignores data outside the window", () => {
    const { intake, trend } = simulate({ intake: 2000, expenditure: 2500 });
    const old: IntakeCalories[] = [{ date: addDays(windowStart, -1), calories: 9000 }];
    const oldTrend: TrendDay[] = [{ date: addDays(windowStart, -1), trendKg: 120 }];
    const estimate = estimateExpenditure({
      intake: [...old, ...intake],
      trend: [...oldTrend, ...trend],
      today,
      calculatorExpenditure: 2800,
    });
    expect(estimate.loggedDays).toBe(21);
    expect(estimate.measured).toBeCloseTo(2500, 6);
  });

  it("falls back to the calculator with too little data", () => {
    const fallback = { measured: null, expenditure: 2800, confidence: 0 };
    const full = simulate({ intake: 2000, expenditure: 2500 });

    // No logged days
    expect(
      estimateExpenditure({ intake: [], trend: full.trend, today, calculatorExpenditure: 2800 }),
    ).toMatchObject(fallback);
    // Fewer than two trend points
    expect(
      estimateExpenditure({
        intake: full.intake,
        trend: full.trend.slice(0, 1),
        today,
        calculatorExpenditure: 2800,
      }),
    ).toMatchObject({ ...fallback, weighIns: 1, trendChangeKg: null });
    // Trend span under seven days
    const short = simulate({ intake: 2000, expenditure: 2500, weighInDays: [14, 20] });
    expect(
      estimateExpenditure({
        intake: full.intake,
        trend: short.trend,
        today,
        calculatorExpenditure: 2800,
      }),
    ).toMatchObject({ ...fallback, weighIns: 2 });
  });

  it("rounds the fallback to the nearest 10", () => {
    const estimate = estimateExpenditure({
      intake: [],
      trend: [],
      today,
      calculatorExpenditure: 2764.3,
    });
    expect(estimate.expenditure).toBe(2760);
  });

  it("accepts a span of exactly seven days", () => {
    const { intake, trend } = simulate({
      intake: 2000,
      expenditure: 2500,
      weighInDays: [13, 20],
    });
    const estimate = estimateExpenditure({ intake, trend, today, calculatorExpenditure: 2800 });
    expect(estimate.measured).toBeCloseTo(2500, 6);
    // confidence = 1 * 2 / 10
    expect(estimate.confidence).toBeCloseTo(0.2, 9);
  });
});

describe("proposeTargets", () => {
  const steady = () => {
    const { intake, trend } = simulate({ intake: 2000, expenditure: 2500 });
    return estimateExpenditure({ intake, trend, today, calculatorExpenditure: 2800 });
  };

  it("moves toward the measured expenditure", () => {
    const estimate = steady();
    const proposal = proposeTargets({
      estimate,
      goal: "lose",
      weeklyRateKg: 0.5,
      weightKg: 80,
      sex: "male",
      current,
      keepOverrides: false,
    });
    // expenditure 2500 - 550 = 1950
    expect(proposal.targets.calories).toBe(1950);
    expect(proposal.dailyAdjustment).toBeCloseTo(-550, 6);
    expect(proposal.floored).toBe(false);
    // protein 144 g; fat 0.25 * 1950 / 9 = 54.2 -> 54 g (above the 48 g minimum)
    expect(proposal.targets.protein).toBe(144);
    expect(proposal.targets.fat).toBe(54);
    expect(proposal.expectedWeeklyChangeKg).toBe(-0.5);
    expect(proposal.actualWeeklyChangeKg).toBeCloseTo(-0.4545, 3);
  });

  it("reports a flat trend and a gain goal with signs", () => {
    const { intake, trend } = simulate({ intake: 2400, expenditure: 2400 });
    const estimate = estimateExpenditure({ intake, trend, today, calculatorExpenditure: 2600 });
    const proposal = proposeTargets({
      estimate,
      goal: "gain",
      weeklyRateKg: 0.25,
      weightKg: 80,
      sex: "male",
      current,
      keepOverrides: false,
    });
    // 2400 + 275 = 2675 -> 2680 (rounded to the nearest 10)
    expect(proposal.targets.calories).toBe(2680);
    expect(proposal.expectedWeeklyChangeKg).toBe(0.25);
    expect(Math.abs(proposal.actualWeeklyChangeKg!)).toBeLessThan(1e-9);
  });

  it("has no actual change when the trend is not measurable", () => {
    const estimate = estimateExpenditure({
      intake: [],
      trend: [],
      today,
      calculatorExpenditure: 2500,
    });
    const proposal = proposeTargets({
      estimate,
      goal: "maintain",
      weeklyRateKg: 0.5,
      weightKg: 80,
      sex: "male",
      current,
      keepOverrides: false,
    });
    expect(proposal.actualWeeklyChangeKg).toBeNull();
    expect(proposal.expectedWeeklyChangeKg).toBe(0);
    expect(proposal.targets.calories).toBe(2500);
  });

  it("applies the calorie floor", () => {
    const estimate = estimateExpenditure({
      intake: [],
      trend: [],
      today,
      calculatorExpenditure: 1400,
    });
    const proposal = proposeTargets({
      estimate,
      goal: "lose",
      weeklyRateKg: 1,
      weightKg: 60,
      sex: "female",
      current,
      keepOverrides: false,
    });
    expect(proposal.floored).toBe(true);
    expect(proposal.targets.calories).toBe(1200);
  });

  it("keeps hand-set values when asked and replaces them otherwise", () => {
    const estimate = steady();
    const overridden = {
      ...current,
      protein: 200,
      fat: 90,
      overridden: { calories: false, protein: true, carbs: false, fat: true },
    };
    const args = {
      estimate,
      goal: "lose" as const,
      weeklyRateKg: 0.5,
      weightKg: 80,
      sex: "male" as const,
      current: overridden,
    };
    const kept = proposeTargets({ ...args, keepOverrides: true });
    expect(kept.targets.calories).toBe(1950);
    expect(kept.targets.protein).toBe(200);
    expect(kept.targets.fat).toBe(90);
    // carbs come from the split: (1950 - 576 - 487.5) / 4 = 221.6 -> 222
    expect(kept.targets.carbs).toBe(222);

    const replaced = proposeTargets({ ...args, keepOverrides: false });
    expect(replaced.targets).toEqual({ calories: 1950, protein: 144, carbs: 222, fat: 54 });
  });

  it("keeps a hand-set calorie target and splits macros around it", () => {
    const estimate = steady();
    const proposal = proposeTargets({
      estimate,
      goal: "lose",
      weeklyRateKg: 0.5,
      weightKg: 80,
      sex: "male",
      current: { ...current, calories: 2000, overridden: { ...noOverrides, calories: true } },
      keepOverrides: true,
    });
    expect(proposal.targets.calories).toBe(2000);
    // protein 144 g, fat 0.25 * 2000 / 9 = 55.6 -> 56 g
    expect(proposal.targets.protein).toBe(144);
    expect(proposal.targets.fat).toBe(56);
  });
});
