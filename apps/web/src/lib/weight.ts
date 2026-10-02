import {
  addDays,
  daysBetween,
  fromKg,
  type IntakeDay,
  roundWeight,
  toKg,
  type TrendPoint,
  WEIGHT_LIMITS,
  type WeightUnit,
} from "@cauldron/shared";
import { parseNumber } from "./targets";

// Pure helpers behind the weight page (#117): reading a typed weight, the
// chart's scales and paths, and averages over the logged days.

/** The lowest and highest weight to accept in `unit`, rounded so both ends are valid. */
export const weightLimits = (unit: WeightUnit) => ({
  min: Math.ceil(fromKg(WEIGHT_LIMITS.min, unit) * 10) / 10,
  max: Math.floor(fromKg(WEIGHT_LIMITS.max, unit) * 10) / 10,
});

/** A typed weight in `unit` as kilograms, or null when it isn't a number in range. */
export const parseWeight = (text: string, unit: WeightUnit): number | null => {
  const n = parseNumber(text);
  if (n === null) return null;
  const rounded = roundWeight(n);
  const { min, max } = weightLimits(unit);
  return rounded < min || rounded > max ? null : toKg(rounded, unit);
};

/** A change in weight with its sign, to one decimal: "+0.4", "−1.2", "0.0". */
export const signedChange = (deltaKg: number, unit: WeightUnit): string => {
  const value = roundWeight(fromKg(deltaKg, unit));
  if (value === 0) return "0.0";
  return `${value > 0 ? "+" : "−"}${Math.abs(value).toFixed(1)}`;
};

/** Evenly spaced round values covering [min, max], about `target` of them. */
export const niceTicks = (min: number, max: number, target = 4): ReadonlyArray<number> => {
  if (max <= min) {
    const mid = Math.round(min);
    return [mid - 1, mid, mid + 1];
  }
  const rough = (max - min) / target;
  const magnitude = 10 ** Math.floor(Math.log10(rough));
  const step = ([1, 2, 5, 10].find((m) => m * magnitude >= rough) ?? 10) * magnitude;
  const first = Math.floor(min / step) * step;
  const last = Math.ceil(max / step) * step;
  const ticks: Array<number> = [];
  for (let v = first; v <= last + step / 2; v += step) ticks.push(Number(v.toFixed(6)));
  return ticks;
};

export interface Chart {
  readonly width: number;
  readonly height: number;
  readonly plot: {
    readonly left: number;
    readonly right: number;
    readonly top: number;
    readonly bottom: number;
  };
  readonly yTicks: ReadonlyArray<{ readonly value: number; readonly y: number }>;
  readonly xTicks: ReadonlyArray<{ readonly date: string; readonly x: number }>;
  readonly dots: ReadonlyArray<{ readonly date: string; readonly x: number; readonly y: number }>;
  /** The trend as an SVG path, empty with no points. */
  readonly line: string;
}

/**
 * Lays the weigh-ins and their trend out in a `width` x `height` box, with the
 * x axis running from `start` to `end` and the y axis in `unit`.
 */
export const buildChart = (
  points: ReadonlyArray<TrendPoint>,
  unit: WeightUnit,
  start: string,
  end: string,
  size: { width: number; height: number } = { width: 640, height: 260 },
): Chart => {
  const plot = { left: 48, right: size.width - 12, top: 12, bottom: size.height - 28 };
  const values = points.flatMap((p) => [fromKg(p.weightKg, unit), fromKg(p.trendKg, unit)]);
  const ticks = values.length === 0 ? [0, 1] : niceTicks(Math.min(...values), Math.max(...values));
  const lo = ticks[0]!;
  const hi = ticks[ticks.length - 1]!;
  const span = Math.max(1, daysBetween(start, end));
  const x = (date: string) =>
    plot.left +
    (Math.min(span, Math.max(0, daysBetween(start, date))) / span) * (plot.right - plot.left);
  const y = (value: number) => plot.bottom - ((value - lo) / (hi - lo)) * (plot.bottom - plot.top);

  const xDates = [...new Set([0, 1, 2, 3].map((i) => addDays(start, Math.round((span * i) / 3))))];
  return {
    ...size,
    plot,
    yTicks: ticks.map((value) => ({ value, y: y(value) })),
    xTicks: xDates.map((date) => ({ date, x: x(date) })),
    dots: points.map((p) => ({ date: p.date, x: x(p.date), y: y(fromKg(p.weightKg, unit)) })),
    line: points
      .map(
        (p, i) =>
          `${i === 0 ? "M" : "L"}${x(p.date).toFixed(1)} ${y(fromKg(p.trendKg, unit)).toFixed(1)}`,
      )
      .join(" "),
  };
};

/** Average daily intake over the days that have food logged; null with none. */
export const averageIntake = (days: ReadonlyArray<IntakeDay>) => {
  const logged = days.filter((d) => d.entries > 0);
  if (logged.length === 0) return null;
  const mean = (key: "calories" | "protein" | "carbs" | "fat") =>
    logged.reduce((sum, d) => sum + d.totals[key], 0) / logged.length;
  return {
    days: logged.length,
    calories: mean("calories"),
    protein: mean("protein"),
    carbs: mean("carbs"),
    fat: mean("fat"),
  };
};
