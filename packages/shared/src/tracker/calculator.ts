// Calorie and macro targets from body stats and a goal: Mifflin-St Jeor resting
// energy, an activity multiplier, a weekly rate of change and a macro split.
// Pure arithmetic, no Effect and no I/O.

import { type ActivityLevel, type Goal, type Sex, TRACKER_LIMITS } from "../Tracker.ts";

/** Resting energy multiplier for each activity level. */
export const ACTIVITY_MULTIPLIERS: Record<ActivityLevel, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  active: 1.725,
  veryActive: 1.9,
};

/** Constants and guard rails the calculator applies. */
export const CALCULATOR_LIMITS = {
  KCAL_PER_KG: 7700,
  maxWeeklyRateKg: { lose: 1.0, gain: 0.5 },
  proteinPerKg: { default: 1.8, min: 1.2, max: 3.0 },
  fatShare: { default: 0.25, min: 0.2, max: 0.4 },
  minFatPerKg: 0.6,
  calorieFloor: { female: 1200, male: 1500, unspecified: 1350 } satisfies Record<Sex, number>,
} as const;

const PROTEIN_KCAL = 4;
const CARB_KCAL = 4;
const FAT_KCAL = 9;

/** Whole years between `birthDate` and `today` (both `YYYY-MM-DD`). */
export const ageOn = (birthDate: string, today: string): number => {
  const [by, bm, bd] = birthDate.split("-").map(Number) as [number, number, number];
  const [ty, tm, td] = today.split("-").map(Number) as [number, number, number];
  const hadBirthday = tm > bm || (tm === bm && td >= bd);
  return ty - by - (hadBirthday ? 0 : 1);
};

const SEX_CONSTANT: Record<Sex, number> = { male: 5, female: -161, unspecified: -78 };

/** Resting energy in kcal per day (Mifflin-St Jeor). */
export const restingEnergy = (input: {
  readonly sex: Sex;
  readonly ageYears: number;
  readonly heightCm: number;
  readonly weightKg: number;
}): number =>
  10 * input.weightKg + 6.25 * input.heightCm - 5 * input.ageYears + SEX_CONSTANT[input.sex];

/** Daily calories and macro grams. */
export interface MacroTargets {
  readonly calories: number;
  readonly protein: number;
  readonly carbs: number;
  readonly fat: number;
}

/**
 * Split a calorie target into macros: protein by bodyweight, fat as a share of
 * calories (never below the per-kg minimum), carbs fill the rest (never negative).
 * Grams are whole numbers.
 */
export const splitMacros = (input: {
  readonly calories: number;
  readonly weightKg: number;
  readonly proteinPerKg?: number | undefined;
  readonly fatShare?: number | undefined;
}): MacroTargets => {
  const { calories, weightKg } = input;
  const protein = (input.proteinPerKg ?? CALCULATOR_LIMITS.proteinPerKg.default) * weightKg;
  const fatShare = input.fatShare ?? CALCULATOR_LIMITS.fatShare.default;
  const fat = Math.max((fatShare * calories) / FAT_KCAL, CALCULATOR_LIMITS.minFatPerKg * weightKg);
  const carbs = Math.max(0, (calories - PROTEIN_KCAL * protein - FAT_KCAL * fat) / CARB_KCAL);
  // Held inside what the targets accept, so an extreme profile still saves.
  const grams = (n: number) =>
    Math.min(TRACKER_LIMITS.grams.max, Math.max(TRACKER_LIMITS.grams.min, Math.round(n)));
  return {
    calories: Math.min(
      TRACKER_LIMITS.calories.max,
      Math.max(TRACKER_LIMITS.calories.min, Math.round(calories)),
    ),
    protein: grams(protein),
    carbs: grams(carbs),
    fat: grams(fat),
  };
};

/** The weekly rate in kg, clamped to what the goal allows (0 for maintain). */
export const clampWeeklyRate = (goal: Goal, weeklyRateKg: number): number =>
  goal === "maintain"
    ? 0
    : Math.min(Math.max(0, weeklyRateKg), CALCULATOR_LIMITS.maxWeeklyRateKg[goal]);

/** Signed daily kcal change for a goal at a weekly rate (negative to lose). */
export const dailyAdjustmentFor = (goal: Goal, weeklyRateKg: number): number => {
  const rate = clampWeeklyRate(goal, weeklyRateKg);
  const sign = goal === "lose" ? -1 : 1;
  return (sign * rate * CALCULATOR_LIMITS.KCAL_PER_KG) / 7;
};

/** Calories for a goal: expenditure plus adjustment, floored, to the nearest 10. */
export const goalCalories = (input: {
  readonly sex: Sex;
  readonly expenditure: number;
  readonly goal: Goal;
  readonly weeklyRateKg: number;
}): { readonly calories: number; readonly floored: boolean; readonly dailyAdjustment: number } => {
  const dailyAdjustment = dailyAdjustmentFor(input.goal, input.weeklyRateKg);
  const floor = CALCULATOR_LIMITS.calorieFloor[input.sex];
  const raw = input.expenditure + dailyAdjustment;
  const floored = raw < floor;
  const calories = Math.min(
    TRACKER_LIMITS.calories.max,
    Math.round(Math.max(floor, raw) / 10) * 10,
  );
  return { calories, floored, dailyAdjustment };
};

export interface CalculatorInput {
  readonly sex: Sex;
  readonly birthDate: string;
  readonly heightCm: number;
  readonly weightKg: number;
  readonly activity: ActivityLevel;
  readonly goal: Goal;
  /** Positive kg per week; ignored for maintain and clamped to the goal's maximum. */
  readonly weeklyRateKg: number;
  readonly proteinPerKg?: number | undefined;
  readonly fatShare?: number | undefined;
  readonly today: string;
}

export interface CalculatorResult {
  readonly restingEnergy: number;
  readonly expenditure: number;
  /** Signed kcal per day, negative to lose. */
  readonly dailyAdjustment: number;
  /** After clamping; 0 for maintain. */
  readonly weeklyRateKg: number;
  /** True when the calorie floor raised the target. */
  readonly floored: boolean;
  readonly targets: MacroTargets;
}

/** Daily targets for a person and a goal. */
export const calculateTargets = (input: CalculatorInput): CalculatorResult => {
  const resting = restingEnergy({
    sex: input.sex,
    ageYears: ageOn(input.birthDate, input.today),
    heightCm: input.heightCm,
    weightKg: input.weightKg,
  });
  const expenditure = resting * ACTIVITY_MULTIPLIERS[input.activity];
  const { calories, floored, dailyAdjustment } = goalCalories({
    sex: input.sex,
    expenditure,
    goal: input.goal,
    weeklyRateKg: input.weeklyRateKg,
  });
  return {
    restingEnergy: resting,
    expenditure,
    dailyAdjustment,
    weeklyRateKg: clampWeeklyRate(input.goal, input.weeklyRateKg),
    floored,
    targets: splitMacros({
      calories,
      weightKg: input.weightKg,
      proteinPerKg: input.proteinPerKg,
      fatShare: input.fatShare,
    }),
  };
};
