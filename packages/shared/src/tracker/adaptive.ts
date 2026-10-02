// Adaptive targets from what was actually logged: average intake over a recent
// window minus the energy the weight trend says was stored or burned gives a
// measured expenditure, blended with the calculator's estimate by how much data
// there is. Pure arithmetic, no Effect and no I/O.

import { addDays, daysBetween } from "../dates.ts";
import type { Goal, Sex, TargetOverrides } from "../Tracker.ts";
import {
  CALCULATOR_LIMITS,
  clampWeeklyRate,
  goalCalories,
  type MacroTargets,
  splitMacros,
} from "./calculator.ts";

/** Calories logged on a day. Callers pass only days with something logged. */
export interface IntakeCalories {
  readonly date: string;
  readonly calories: number;
}

/** Trend weight on a day (from weigh-ins); may have gaps. */
export interface TrendDay {
  readonly date: string;
  readonly trendKg: number;
}

export const ADAPTIVE_LIMITS = {
  /** Days in the measurement window, ending today. */
  windowDays: 21,
  /** Minimum days between the first and last trend points in the window. */
  minTrendSpanDays: 7,
  fullConfidenceLoggedDays: 14,
  fullConfidenceWeighIns: 10,
} as const;

export interface ExpenditureEstimate {
  /** Energy balance measurement, or null when there is too little data. */
  readonly measured: number | null;
  /** Measured and calculator values blended by confidence, to the nearest 10. */
  readonly expenditure: number;
  /** 0 to 1. */
  readonly confidence: number;
  readonly loggedDays: number;
  readonly weighIns: number;
  readonly windowDays: number;
  /** Last minus first trend weight in the window, null when not measurable. */
  readonly trendChangeKg: number | null;
  /** Days between the first and last trend points used, null when not measurable. */
  readonly spanDays: number | null;
}

const roundTo10 = (n: number) => Math.round(n / 10) * 10;

/** Estimate daily expenditure from logged intake and trend weight. */
export const estimateExpenditure = (input: {
  readonly intake: ReadonlyArray<IntakeCalories>;
  readonly trend: ReadonlyArray<TrendDay>;
  readonly today: string;
  readonly calculatorExpenditure: number;
}): ExpenditureEstimate => {
  const windowDays = ADAPTIVE_LIMITS.windowDays;
  const start = addDays(input.today, -(windowDays - 1));
  const inWindow = (date: string) => date >= start && date <= input.today;

  // One entry per day: a repeated date keeps its last value.
  const loggedByDay = new Map<string, number>();
  for (const day of input.intake) if (inWindow(day.date)) loggedByDay.set(day.date, day.calories);
  const trendByDay = new Map<string, number>();
  for (const point of input.trend) {
    if (inWindow(point.date)) trendByDay.set(point.date, point.trendKg);
  }

  const loggedDays = loggedByDay.size;
  const trend = [...trendByDay.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  const weighIns = trend.length;

  const first = trend[0];
  const last = trend[trend.length - 1];
  const spanDays = first && last ? daysBetween(first[0], last[0]) : null;
  const measurable =
    loggedDays > 0 &&
    first !== undefined &&
    last !== undefined &&
    weighIns >= 2 &&
    spanDays !== null &&
    spanDays >= ADAPTIVE_LIMITS.minTrendSpanDays;

  if (!measurable) {
    const trendChangeKg = first && last && weighIns >= 2 ? last[1] - first[1] : null;
    return {
      measured: null,
      expenditure: roundTo10(input.calculatorExpenditure),
      confidence: 0,
      loggedDays,
      weighIns,
      windowDays,
      trendChangeKg,
      spanDays: weighIns >= 2 ? spanDays : null,
    };
  }

  const averageIntake = [...loggedByDay.values()].reduce((sum, c) => sum + c, 0) / loggedDays;
  const trendChangeKg = last[1] - first[1];
  const measured = averageIntake - (trendChangeKg * CALCULATOR_LIMITS.KCAL_PER_KG) / spanDays;
  const confidence =
    Math.min(1, loggedDays / ADAPTIVE_LIMITS.fullConfidenceLoggedDays) *
    Math.min(1, weighIns / ADAPTIVE_LIMITS.fullConfidenceWeighIns);

  return {
    measured,
    expenditure: roundTo10(confidence * measured + (1 - confidence) * input.calculatorExpenditure),
    confidence,
    loggedDays,
    weighIns,
    windowDays,
    trendChangeKg,
    spanDays,
  };
};

export interface ProposedTargets {
  readonly targets: MacroTargets;
  /** True when the calorie floor raised the target. */
  readonly floored: boolean;
  /** Signed kcal per day from the goal, negative to lose. */
  readonly dailyAdjustment: number;
  /** What the goal asks for, signed (negative to lose, 0 to maintain). */
  readonly expectedWeeklyChangeKg: number;
  /** What the trend shows per week, null when not measurable. */
  readonly actualWeeklyChangeKg: number | null;
}

/** Propose new targets from an expenditure estimate, optionally keeping hand-set values. */
export const proposeTargets = (input: {
  readonly estimate: ExpenditureEstimate;
  readonly goal: Goal;
  readonly weeklyRateKg: number;
  readonly weightKg: number;
  readonly sex: Sex;
  readonly proteinPerKg?: number | undefined;
  readonly fatShare?: number | undefined;
  readonly current: MacroTargets & { readonly overridden: TargetOverrides };
  readonly keepOverrides: boolean;
}): ProposedTargets => {
  const { current, keepOverrides } = input;
  const rate = clampWeeklyRate(input.goal, input.weeklyRateKg);
  const goalResult = goalCalories({
    sex: input.sex,
    expenditure: input.estimate.expenditure,
    goal: input.goal,
    weeklyRateKg: input.weeklyRateKg,
  });

  // A hand-set calorie target stays the basis for the macro split.
  const keepCalories = keepOverrides && current.overridden.calories;
  const split = splitMacros({
    calories: keepCalories ? current.calories : goalResult.calories,
    weightKg: input.weightKg,
    proteinPerKg: input.proteinPerKg,
    fatShare: input.fatShare,
  });
  const keep = (field: keyof TargetOverrides) => keepOverrides && current.overridden[field];

  const { trendChangeKg, spanDays } = input.estimate;
  return {
    targets: {
      calories: keep("calories") ? current.calories : split.calories,
      protein: keep("protein") ? current.protein : split.protein,
      carbs: keep("carbs") ? current.carbs : split.carbs,
      fat: keep("fat") ? current.fat : split.fat,
    },
    floored: goalResult.floored,
    dailyAdjustment: goalResult.dailyAdjustment,
    expectedWeeklyChangeKg: input.goal === "lose" ? -rate : rate,
    actualWeeklyChangeKg:
      trendChangeKg !== null && spanDays !== null && spanDays > 0
        ? (trendChangeKg / spanDays) * 7
        : null,
  };
};
