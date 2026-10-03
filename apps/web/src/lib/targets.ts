import {
  CALCULATOR_LIMITS,
  cmToFeetInches,
  feetInchesToCm,
  fromKg,
  type Goal,
  type HeightUnit,
  roundWeight,
  splitMacros,
  toKg,
  type WeightUnit,
} from "@cauldron/shared";
import { Schema } from "effect";

// Pure helpers behind the "set your targets" page: reading what was typed,
// the weekly rate choices in the cook's unit, and which targets are theirs.

/** A number typed by hand: accepts a decimal comma, null when empty or not a number. */
export const parseNumber = (text: string): number | null => {
  const trimmed = text.trim().replace(",", ".");
  if (trimmed === "") return null;
  const n = Number(trimmed);
  return Number.isFinite(n) ? n : null;
};

/** A number for an input: up to one decimal, no trailing ".0". */
export const showNumber = (n: number, digits = 1): string => String(Number(n.toFixed(digits)));

/** Centimetres from what was typed in the chosen unit; null when incomplete. */
export const heightToCm = (
  unit: HeightUnit,
  v: { readonly cm: string; readonly feet: string; readonly inches: string },
): number | null => {
  if (unit === "cm") return parseNumber(v.cm);
  const feet = parseNumber(v.feet);
  const inches = v.inches.trim() === "" ? 0 : parseNumber(v.inches);
  return feet === null || inches === null ? null : feetInchesToCm(feet, inches);
};

/** The inputs for a height in centimetres. */
export const heightFields = (cm: number) => {
  const { feet, inches } = cmToFeetInches(cm);
  return { cm: showNumber(cm), feet: String(feet), inches: showNumber(inches) };
};

/** A weight shown in the cook's unit, to one decimal. */
export const showWeight = (kg: number, unit: WeightUnit): string =>
  showNumber(roundWeight(fromKg(kg, unit)));

/** A weight for reading, in the cook's unit: always one decimal, so 73.0 doesn't read as 73. */
export const weightLabel = (kg: number, unit: WeightUnit): string =>
  roundWeight(fromKg(kg, unit)).toFixed(1);

/** A rate on offer, as shown (in the cook's unit) and as stored (kilograms). */
export interface RateChoice {
  readonly amount: number;
  readonly kg: number;
}

const RATE_AMOUNTS: Record<WeightUnit, Record<"lose" | "gain", ReadonlyArray<number>>> = {
  kg: { lose: [0.25, 0.5, 0.75, 1], gain: [0.25, 0.5] },
  lb: { lose: [0.5, 1, 1.5, 2], gain: [0.5, 1] },
};

/** Weekly rates to choose from; none when maintaining. Lose up to 1 kg (2 lb), gain up to 0.5 kg (1 lb). */
export const rateChoices = (goal: Goal, unit: WeightUnit): ReadonlyArray<RateChoice> =>
  goal === "maintain"
    ? []
    : RATE_AMOUNTS[unit][goal].map((amount) => ({
        amount,
        kg: Math.min(toKg(amount, unit), CALCULATOR_LIMITS.maxWeeklyRateKg[goal]),
      }));

/** The default rate for a goal: half a kilo (or one pound) a week. */
export const defaultRate = (goal: Goal, unit: WeightUnit): number | null =>
  rateChoices(goal, unit).find((c) => c.amount === (unit === "kg" ? 0.5 : 1))?.amount ?? null;

/** The choice closest to a stored rate in kilograms, as its amount. */
export const nearestRate = (goal: Goal, unit: WeightUnit, kg: number): number | null => {
  const choices = rateChoices(goal, unit);
  if (choices.length === 0) return null;
  return choices.reduce((best, c) => (Math.abs(c.kg - kg) < Math.abs(best.kg - kg) ? c : best))
    .amount;
};

export const TARGET_KEYS = ["calories", "protein", "carbs", "fat"] as const;
export type TargetKey = (typeof TARGET_KEYS)[number];

/** Targets typed in by hand, as typed. A key is here only while it's overridden. */
export type Overrides = Partial<Record<TargetKey, string>>;

export interface ResolvedTargets {
  readonly values: Record<TargetKey, number>;
  readonly overridden: Record<TargetKey, boolean>;
}

/**
 * The four targets: what was calculated, with the cook's own numbers on top.
 * When calories are overridden the other macros are re-split from that number,
 * so the grams still add up; macros the cook set stay as set.
 */
export const resolveTargets = (input: {
  readonly calculated: Record<TargetKey, number>;
  readonly overrides: Overrides;
  readonly weightKg: number;
  readonly proteinPerKg: number | undefined;
  readonly fatShare: number | undefined;
}): ResolvedTargets => {
  const typed = (key: TargetKey): number | null =>
    input.overrides[key] === undefined ? null : parseNumber(input.overrides[key]);
  const calories = typed("calories") ?? input.calculated.calories;
  const split =
    typed("calories") === null
      ? input.calculated
      : splitMacros({
          calories,
          weightKg: input.weightKg,
          proteinPerKg: input.proteinPerKg,
          fatShare: input.fatShare,
        });
  const pick = (key: "protein" | "carbs" | "fat") => typed(key) ?? split[key];
  return {
    values: { calories, protein: pick("protein"), carbs: pick("carbs"), fat: pick("fat") },
    overridden: {
      calories: input.overrides.calories !== undefined,
      protein: input.overrides.protein !== undefined,
      carbs: input.overrides.carbs !== undefined,
      fat: input.overrides.fat !== undefined,
    },
  };
};

/** The first message when `value` fails `schema`, or undefined when it passes. */
export const firstIssue = (schema: Schema.Codec<any, any>, value: unknown): string | undefined => {
  const result = Schema.toStandardSchemaV1(schema)["~standard"].validate(value);
  if (result instanceof Promise || !result.issues) return undefined;
  return result.issues[0]?.message;
};
