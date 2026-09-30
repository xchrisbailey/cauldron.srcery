import { quantities } from "../copy.ts";
import type { Quantity, UnitCode } from "./schema.ts";
import { convertForDisplay, UNITS } from "./units.ts";

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
  [1 / 6, "⅙"],
  [1 / 4, "¼"],
  [1 / 3, "⅓"],
  [3 / 8, "⅜"],
  [1 / 2, "½"],
  [5 / 8, "⅝"],
  [2 / 3, "⅔"],
  [3 / 4, "¾"],
  [5 / 6, "⅚"],
  [7 / 8, "⅞"],
  [1, ""],
];

/**
 * "1 ½", "¾", "2": nearest measurable fraction. Amounts below 1/16, which would
 * round up to ⅛ and inflate the amount, show as a decimal instead. Positive
 * values never display as 0.
 */
function formatFraction(value: number): string {
  if (value <= 0) return "0";
  if (value < 1 / 16) return formatDecimal(value);
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

const PINCH_ML = UNITS.tsp.factor / 16;

/**
 * Quantity plus unit label: "1 ½ c", "250 g", "2–3 cloves". Small US volumes
 * step down first (1/8 cup is "2 tbsp", 1/2 tbsp is "1 ½ tsp"), and anything
 * below 1/16 tsp reads "pinch" rather than an amount.
 */
export function formatMeasure(quantity: Quantity, unit: UnitCode | null): string {
  if (unit === null) return formatQuantity(quantity, unit);
  let q = quantity;
  let u: UnitCode = unit;
  const def = UNITS[unit];
  if (def.dimension === "volume" && def.system === "us" && unit !== "pinch" && unit !== "dash") {
    const top = quantity.max ?? quantity.min;
    if (top * def.factor < PINCH_ML) return quantities.pinch.text;
    const next = convertForDisplay(top, unit, "us").unit;
    if (next !== unit) {
      u = next;
      q = {
        min: (quantity.min * def.factor) / UNITS[next].factor,
        max: quantity.max === null ? null : (quantity.max * def.factor) / UNITS[next].factor,
      };
    }
  }
  const text = formatQuantity(q, u);
  const d = UNITS[u];
  const top = q.max ?? q.min;
  return `${text} ${d.abbr ?? (top > 1 ? d.plural : d.singular)}`;
}
