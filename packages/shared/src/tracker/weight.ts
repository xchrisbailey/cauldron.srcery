// Weight tracking maths: unit conversion and the smoothed trend line. Pure
// functions over plain data, so the API, the web app and the iOS contract all
// agree. Weights are stored in kilograms; units are a display concern.

import { addDays, daysBetween } from "../dates.ts";
import { TRACKER_LIMITS, type WeighIn, type WeightUnit } from "../Tracker.ts";

/** Kilograms in one pound. */
export const KG_PER_LB = 0.45359237;

export const WEIGHT_LIMITS = TRACKER_LIMITS.weightKg;

/** A weight in the given unit, as kilograms. */
export const toKg = (value: number, unit: WeightUnit): number =>
  unit === "kg" ? value : value * KG_PER_LB;

/** Kilograms as a weight in the given unit. */
export const fromKg = (kg: number, unit: WeightUnit): number =>
  unit === "kg" ? kg : kg / KG_PER_LB;

/** Round to one decimal place, the precision the scale and the UI use. */
export const roundWeight = (value: number): number => Math.round(value * 10) / 10;

const CM_PER_INCH = 2.54;

/** Centimetres as feet and inches (inches to one decimal, never 12). */
export const cmToFeetInches = (cm: number): { feet: number; inches: number } => {
  const totalInches = cm / CM_PER_INCH;
  let feet = Math.floor(totalInches / 12);
  let inches = Math.round((totalInches - feet * 12) * 10) / 10;
  if (inches >= 12) {
    feet += 1;
    inches = 0;
  }
  return { feet, inches };
};

/** Feet and inches as centimetres. */
export const feetInchesToCm = (feet: number, inches: number): number =>
  (feet * 12 + inches) * CM_PER_INCH;

/** A weigh-in with the smoothed trend as of that day. */
export interface TrendPoint {
  readonly date: string;
  readonly weightKg: number;
  readonly trendKg: number;
}

/** How far the trend moves toward each new weight, per day (Hacker's Diet). */
export const TREND_SMOOTHING = 0.1;

/**
 * The exponentially smoothed trend for each weigh-in, oldest first. Duplicate
 * days keep the last entry given. A gap of `n` days uses `1 - (1 - alpha)^n`,
 * so a missed week counts as a week of smoothing rather than one step.
 */
export const trendSeries = (weighIns: ReadonlyArray<WeighIn>): Array<TrendPoint> => {
  const byDate = new Map<string, number>();
  for (const w of weighIns) byDate.set(w.date, w.weightKg);
  const days = [...byDate.keys()].sort();

  const out: Array<TrendPoint> = [];
  let prevDate: string | null = null;
  let trend = 0;
  for (const date of days) {
    const weightKg = byDate.get(date)!;
    if (prevDate === null) {
      trend = weightKg;
    } else {
      const alpha = 1 - (1 - TREND_SMOOTHING) ** daysBetween(prevDate, date);
      trend += alpha * (weightKg - trend);
    }
    out.push({ date, weightKg, trendKg: trend });
    prevDate = date;
  }
  return out;
};

/** The trend on `date`: the last point at or before it, or null if none. */
export const trendOn = (series: ReadonlyArray<TrendPoint>, date: string): number | null => {
  let found: number | null = null;
  for (const point of series) {
    if (point.date > date) break;
    found = point.trendKg;
  }
  return found;
};

/** How much the trend moved over the last `days` days, or null without data. */
export const trendChange = (
  series: ReadonlyArray<TrendPoint>,
  days: number,
  today: string,
): number | null => {
  const now = trendOn(series, today);
  const before = trendOn(series, addDays(today, -days));
  return now === null || before === null ? null : now - before;
};

export const RANGES = ["1m", "3m", "1y", "all"] as const;
export type WeightRange = (typeof RANGES)[number];

const RANGE_DAYS = { "1m": 30, "3m": 91, "1y": 365 } as const;

/** The first day a chart range covers, or null for all time. */
export const rangeStart = (range: WeightRange, today: string): string | null =>
  range === "all" ? null : addDays(today, -RANGE_DAYS[range]);
