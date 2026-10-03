import { describe, expect, it } from "vite-plus/test";
import {
  ACTIVITY_MULTIPLIERS,
  adjustedWeight,
  ageOn,
  calculateTargets,
  type CalculatorInput,
  restingEnergy,
  splitMacros,
} from "../src/index.ts";

const base: CalculatorInput = {
  sex: "male",
  birthDate: "1996-03-15",
  heightCm: 180,
  weightKg: 80,
  activity: "moderate",
  goal: "maintain",
  weeklyRateKg: 0,
  today: "2026-10-05",
};

describe("ageOn", () => {
  it("counts whole years and rolls over on the birthday", () => {
    expect(ageOn("1996-10-06", "2026-10-05")).toBe(29);
    expect(ageOn("1996-10-05", "2026-10-05")).toBe(30);
    expect(ageOn("1996-10-04", "2026-10-05")).toBe(30);
    expect(ageOn("1996-11-01", "2026-10-05")).toBe(29);
  });

  it("treats a leap day birthday as passed on 1 March in a common year", () => {
    expect(ageOn("2000-02-29", "2026-02-28")).toBe(25);
    expect(ageOn("2000-02-29", "2026-03-01")).toBe(26);
  });
});

describe("restingEnergy", () => {
  it("uses the Mifflin-St Jeor constants for each sex", () => {
    const stats = { ageYears: 30, heightCm: 180, weightKg: 80 };
    // 10*80 + 6.25*180 - 5*30 = 800 + 1125 - 150 = 1775
    expect(restingEnergy({ ...stats, sex: "male" })).toBe(1780);
    expect(restingEnergy({ ...stats, sex: "female" })).toBe(1614);
    expect(restingEnergy({ ...stats, sex: "unspecified" })).toBe(1697);
  });
});

describe("calculateTargets", () => {
  it("maintains: male, 30, 180 cm, 80 kg, moderate", () => {
    const result = calculateTargets(base);
    // resting = 800 + 1125 - 150 + 5 = 1780
    expect(result.restingEnergy).toBe(1780);
    // expenditure = 1780 * 1.55 = 2759
    expect(result.expenditure).toBeCloseTo(2759, 6);
    expect(result.dailyAdjustment).toBe(0);
    expect(result.weeklyRateKg).toBe(0);
    expect(result.floored).toBe(false);
    // calories = 2759 -> 2760
    // protein = 1.8 * 80 = 144 g; fat = 0.25 * 2760 / 9 = 76.67 -> 77 g
    // carbs = (2760 - 576 - 690) / 4 = 373.5 (rounding may fall either way)
    expect(result.targets.calories).toBe(2760);
    expect(result.targets.protein).toBe(144);
    expect(result.targets.fat).toBe(77);
    expect(Math.abs(result.targets.carbs - 373.5)).toBeLessThanOrEqual(0.5);
  });

  it("loses: female, 35, 165 cm, 70 kg, light, 0.5 kg a week", () => {
    const result = calculateTargets({
      ...base,
      sex: "female",
      birthDate: "1991-01-10",
      heightCm: 165,
      weightKg: 70,
      activity: "light",
      goal: "lose",
      weeklyRateKg: 0.5,
    });
    // resting = 700 + 1031.25 - 175 - 161 = 1395.25
    // BMI 25.7, so adjusted = 68.0625 + 0.25 * (70 - 68.0625) = 68.546875
    // activity = 0.375 * (685.46875 + 1031.25 - 175 - 161) = 517.77
    // expenditure = 1395.25 + 517.77 = 1913.02
    expect(result.adjustedWeightKg).toBeCloseTo(68.546875, 6);
    expect(result.expenditure).toBeCloseTo(1913.01953125, 5);
    // adjustment = -0.5 * 7700 / 7 = -550
    expect(result.dailyAdjustment).toBeCloseTo(-550, 6);
    expect(result.weeklyRateKg).toBe(0.5);
    expect(result.floored).toBe(false);
    // calories = 1363.02 -> 1360
    // protein = 1.8 * 68.55 = 123.4 g; fat share gives 37.8 g but the minimum is 0.6 * 68.55 = 41.1 g
    // carbs = (1360 - 493.5 - 370.2) / 4 = 124.1 g
    expect(result.targets).toEqual({ calories: 1360, protein: 123, carbs: 124, fat: 41 });
  });

  it("gains: unspecified, 28, 170 cm, 65 kg, moderate, 0.25 kg a week", () => {
    const result = calculateTargets({
      ...base,
      sex: "unspecified",
      birthDate: "1998-02-01",
      heightCm: 170,
      weightKg: 65,
      goal: "gain",
      weeklyRateKg: 0.25,
    });
    // resting = 650 + 1062.5 - 140 - 78 = 1494.5; expenditure = 1494.5 * 1.55 = 2316.475
    expect(result.restingEnergy).toBe(1494.5);
    // adjustment = +0.25 * 7700 / 7 = +275
    expect(result.dailyAdjustment).toBeCloseTo(275, 6);
    // calories = 2591.475 -> 2590
    // protein = 117 g; fat = 0.25 * 2590 / 9 = 71.94 -> 72 g
    // carbs = (2590 - 468 - 647.5) / 4 = 368.6 -> 369 g
    expect(result.targets).toEqual({ calories: 2590, protein: 117, carbs: 369, fat: 72 });
  });

  it("applies the calorie floor and says so", () => {
    const result = calculateTargets({
      ...base,
      sex: "female",
      birthDate: "2001-06-01",
      heightCm: 150,
      weightKg: 45,
      activity: "sedentary",
      goal: "lose",
      weeklyRateKg: 1,
    });
    // resting = 450 + 937.5 - 125 - 161 = 1101.5; expenditure = 1321.8
    // 1321.8 - 1100 = 221.8, below the 1200 floor for women
    expect(result.floored).toBe(true);
    // protein = 81 g; fat = 0.25 * 1200 / 9 = 33.3 -> 33 g (minimum 27 g); carbs = (1200 - 324 - 300) / 4 = 144 g
    expect(result.targets).toEqual({ calories: 1200, protein: 81, carbs: 144, fat: 33 });
  });

  it("uses each sex's own floor", () => {
    const small = { ...base, weightKg: 45, heightCm: 150, goal: "lose", weeklyRateKg: 1 } as const;
    expect(calculateTargets(small).targets.calories).toBe(1500);
    expect(calculateTargets({ ...small, sex: "unspecified" }).targets.calories).toBe(1350);
  });

  it("clamps the weekly rate to the goal's maximum", () => {
    const lose = calculateTargets({ ...base, goal: "lose", weeklyRateKg: 2 });
    expect(lose.weeklyRateKg).toBe(1);
    expect(lose.dailyAdjustment).toBeCloseTo(-1100, 6);
    const gain = calculateTargets({ ...base, goal: "gain", weeklyRateKg: 1 });
    expect(gain.weeklyRateKg).toBe(0.5);
    expect(gain.dailyAdjustment).toBeCloseTo(550, 6);
  });

  it("ignores the rate when maintaining", () => {
    const result = calculateTargets({ ...base, goal: "maintain", weeklyRateKg: 0.7 });
    expect(result.weeklyRateKg).toBe(0);
    expect(result.dailyAdjustment).toBe(0);
    expect(result.targets.calories).toBe(2760);
  });

  it("changes with a birthday", () => {
    const before = calculateTargets({ ...base, birthDate: "1996-10-06" });
    const after = calculateTargets({ ...base, birthDate: "1996-10-05" });
    // One year older: resting energy drops by 5, expenditure by 5 * 1.55
    expect(before.restingEnergy - after.restingEnergy).toBe(5);
    expect(before.expenditure - after.expenditure).toBeCloseTo(5 * ACTIVITY_MULTIPLIERS.moderate);
  });

  it("honours custom protein and fat settings", () => {
    const result = calculateTargets({ ...base, proteinPerKg: 2.2, fatShare: 0.35 });
    // protein = 176 g; fat = 0.35 * 2760 / 9 = 107.3 -> 107 g
    expect(result.targets.protein).toBe(176);
    expect(result.targets.fat).toBe(107);
  });
});

describe("splitMacros", () => {
  it("uses the default protein and fat share", () => {
    // protein 144, fat 0.25 * 2000 / 9 = 55.6, carbs (2000 - 576 - 500) / 4 = 231
    expect(splitMacros({ calories: 2000, weightKg: 80 })).toEqual({
      calories: 2000,
      protein: 144,
      carbs: 231,
      fat: 56,
    });
  });

  it("raises fat to the per-kg minimum at a low fat share", () => {
    // 0.2 * 2000 / 9 = 44.4 g, under 0.6 * 80 = 48 g
    const split = splitMacros({ calories: 2000, weightKg: 80, fatShare: 0.2 });
    expect(split.fat).toBe(48);
    // carbs = (2000 - 576 - 432) / 4 = 248
    expect(split.carbs).toBe(248);
  });

  it("never returns negative carbs", () => {
    // protein 180 g (720 kcal) + fat minimum 60 g (540 kcal) already exceed 1000 kcal
    const split = splitMacros({ calories: 1000, weightKg: 100 });
    expect(split.carbs).toBe(0);
    expect(split.protein).toBe(180);
    expect(split.fat).toBe(60);
  });
});

describe("limits", () => {
  it("keeps targets inside what the targets accept at the extremes", () => {
    const big = splitMacros({ calories: 12000, weightKg: 400, proteinPerKg: 3, fatShare: 0.2 });
    expect(big.calories).toBe(10000);
    expect(big.protein).toBe(1000);
    expect(big.fat).toBeLessThanOrEqual(1000);
    expect(big.carbs).toBeLessThanOrEqual(1000);
    const carbsHeavy = splitMacros({
      calories: 9000,
      weightKg: 50,
      proteinPerKg: 1.2,
      fatShare: 0.2,
    });
    expect(carbsHeavy.carbs).toBe(1000);
  });
});

describe("larger bodies", () => {
  it("doses protein and activity by the adjusted weight, not every kilo", () => {
    // Male, 41, 5 ft 9 in (175.26 cm), 396.8 lb (179.98 kg), very active, losing 1.5 lb a week.
    const result = calculateTargets({
      ...base,
      sex: "male",
      birthDate: "1985-01-01",
      heightCm: 175.26,
      weightKg: 179.98,
      activity: "active",
      goal: "lose",
      weeklyRateKg: 0.68,
    });
    // reference = 25 * 1.7526^2 = 76.79; adjusted = 76.79 + 0.25 * 103.19 = 102.59
    expect(result.adjustedWeightKg).toBeCloseTo(102.59, 1);
    // resting = 1799.8 + 1095.4 - 205 + 5 = 2695.2 (real weight)
    expect(result.restingEnergy).toBeCloseTo(2695.2, 0);
    // activity = 0.725 * (1025.9 + 1095.4 - 205 + 5) = 1392.9
    expect(result.activityEnergy).toBeCloseTo(1392.9, 0);
    // expenditure 4088, minus 748 a day for the goal: 3340 (it was 3900 on total weight)
    expect(result.targets.calories).toBe(3340);
    // protein 1.8 * 102.59 = 185 g (it was 324 g on total weight)
    expect(result.targets.protein).toBe(185);
  });

  it("leaves a healthy weight alone", () => {
    expect(adjustedWeight(70, 180)).toBe(70);
  });
});
