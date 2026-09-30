import type { Quantity, UnitCode } from "./schema.ts";
import { UNITS } from "./units.ts";

/** Multiply a quantity (and both ends of a range) by `factor`. */
export function scaleQuantity(quantity: Quantity, factor: number): Quantity {
  return {
    min: quantity.min * factor,
    max: quantity.max === null ? null : quantity.max * factor,
  };
}

// Fractions a cook can measure, as [value, glyph]. Zero and one are the whole-number edges.
const FRACTIONS: readonly (readonly [number, string])[] = [
  [0, ""],
  [1 / 8, "⅛"],
  [1 / 4, "¼"],
  [1 / 3, "⅓"],
  [3 / 8, "⅜"],
  [1 / 2, "½"],
  [5 / 8, "⅝"],
  [2 / 3, "⅔"],
  [3 / 4, "¾"],
  [7 / 8, "⅞"],
  [1, ""],
];

/** "1 ½", "¾", "2": nearest measurable fraction. Positive values never display as 0. */
function formatFraction(value: number): string {
  if (value <= 0) return "0";
  let whole = Math.floor(value);
  const rest = value - whole;
  let best = FRACTIONS[0]!;
  for (const f of FRACTIONS) if (Math.abs(f[0] - rest) < Math.abs(best[0] - rest)) best = f;
  if (best[0] === 1) whole += 1;
  if (best[0] === 0 || best[0] === 1) return whole === 0 ? "⅛" : String(whole);
  return whole === 0 ? best[1] : `${whole} ${best[1]}`;
}

/** 250, 1.5, 12.5, 0.25: trimmed, with precision that shrinks as the value grows. */
function formatDecimal(value: number): string {
  const digits = value >= 100 ? 0 : value >= 10 ? 1 : 2;
  const text = value.toFixed(digits);
  const trimmed = digits === 0 ? text : text.replace(/\.?0+$/, "");
  return trimmed === "0" && value > 0 ? String(Number(value.toPrecision(1))) : trimmed;
}

/**
 * Display text for the quantity only. Metric units get decimals, everything
 * else (US units, pinch, counts, no unit) gets fractions. Ranges use an en
 * dash: "2–3".
 */
export function formatQuantity(quantity: Quantity, unit: UnitCode | null): string {
  const one = unit !== null && UNITS[unit].system === "metric" ? formatDecimal : formatFraction;
  const min = one(quantity.min);
  if (quantity.max === null) return min;
  const max = one(quantity.max);
  return min === max ? min : `${min}–${max}`;
}

/** Quantity plus unit label: "1 ½ c", "250 g", "2–3 cloves". */
export function formatMeasure(quantity: Quantity, unit: UnitCode | null): string {
  const text = formatQuantity(quantity, unit);
  if (unit === null) return text;
  const def = UNITS[unit];
  const top = quantity.max ?? quantity.min;
  return `${text} ${def.abbr ?? (top > 1 ? def.plural : def.singular)}`;
}
