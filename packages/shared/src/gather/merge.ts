import type { Quantity, UnitCode } from "../ingredients/schema.ts";
import { convertForDisplay, UNITS } from "../ingredients/units.ts";
import { type Aisle, aisleFor, AISLES } from "./aisles.ts";

/**
 * Merging the week's ingredient lines into a shopping list (#19).
 *
 * Lines merge when they share an item key (`ingredientKey`) and can be added
 * up: volumes with volumes and masses with masses (converted through ml or
 * g), bare counts with bare counts ("2 onions" + "1 onion"), and count units
 * only with the same unit ("3 cloves" + "4 cloves", never cloves + heads).
 * Cups and grams of the same thing stay as two rows, since there's no density
 * to convert between them. A line with no amount ("salt, to taste") joins an
 * amount-carrying row for the same item when there is one, and is its own row
 * otherwise.
 */

/** One ingredient line from a planned recipe, already scaled by the entry's servings. */
export interface GatherLine {
  readonly recipeId: string;
  readonly item: string;
  readonly itemKey: string;
  readonly quantity: Quantity | null;
  readonly unit: UnitCode | null;
}

/** How much one recipe contributes to a row. */
export interface GatherContribution {
  readonly recipeId: string;
  readonly quantity: Quantity | null;
  readonly unit: UnitCode | null;
}

export interface GatheredRow {
  /** Item key plus how it adds up; stable across regenerations. */
  readonly mergeKey: string;
  readonly itemKey: string;
  /** The item as most of the recipes write it. */
  readonly item: string;
  readonly quantity: Quantity | null;
  readonly unit: UnitCode | null;
  readonly aisle: Aisle;
  readonly sources: ReadonlyArray<GatherContribution>;
}

/** How a measure adds up: "volume", "mass", "count" (bare), "unit:clove", or "none". */
export const measureGroup = (quantity: Quantity | null, unit: UnitCode | null): string => {
  // A unit with no amount adds nothing, the same as no unit.
  if (quantity === null) return "none";
  if (unit === null) return "count";
  const def = UNITS[unit];
  return def.dimension === "count" ? `unit:${unit}` : def.dimension;
};

export const mergeKeyOf = (itemKey: string, quantity: Quantity | null, unit: UnitCode | null) =>
  `${itemKey}|${measureGroup(quantity, unit)}`;

/** A line's amount in the group's base unit (ml, g, or the count itself). */
const toBase = (q: Quantity, unit: UnitCode | null): Quantity => {
  const factor = unit === null ? 1 : UNITS[unit].factor;
  return { min: q.min * factor, max: q.max === null ? null : q.max * factor };
};

const sum = (quantities: ReadonlyArray<Quantity>): Quantity => {
  const ranged = quantities.some((q) => q.max !== null);
  return {
    min: quantities.reduce((n, q) => n + q.min, 0),
    max: ranged ? quantities.reduce((n, q) => n + (q.max ?? q.min), 0) : null,
  };
};

/** The total for a group of lines, in the unit they share, or a sensible one when they differ. */
function total(lines: ReadonlyArray<GatherLine>): {
  quantity: Quantity | null;
  unit: UnitCode | null;
} {
  const measured = lines.filter(
    (l): l is GatherLine & { quantity: Quantity } => l.quantity !== null,
  );
  if (measured.length === 0) return { quantity: null, unit: null };
  const units = new Set(measured.map((l) => l.unit));
  if (units.size === 1) {
    return { quantity: sum(measured.map((l) => l.quantity)), unit: measured[0]!.unit };
  }
  // Mixed volume or mass units: add in ml or g, then show in the cook's system
  // (US if any line used US units), in the unit a shopper reads best.
  const base = sum(measured.map((l) => toBase(l.quantity, l.unit)));
  const volume = UNITS[measured[0]!.unit!].dimension === "volume";
  const us = measured.some((l) => UNITS[l.unit!].system === "us");
  const shown = shoppingUnit(base.max ?? base.min, volume, us);
  const per = UNITS[shown].factor;
  return {
    quantity: { min: base.min / per, max: base.max === null ? null : base.max / per },
    unit: shown,
  };
}

/**
 * The unit for a merged total, from its amount in ml or g: litres and
 * kilograms from 1000, pounds from 1 lb, and cups for US volumes from a
 * quarter cup (a list reads "4 ¼ cups", not "1.06 quarts").
 */
function shoppingUnit(amount: number, volume: boolean, us: boolean): UnitCode {
  if (!us) return amount >= 1000 ? (volume ? "l" : "kg") : volume ? "ml" : "g";
  if (!volume) return amount >= UNITS.lb.factor ? "lb" : "oz";
  if (amount >= UNITS.cup.factor / 4) return "cup";
  return convertForDisplay(amount, "ml", "us").unit;
}

/** The most common way the item is written, first seen winning a tie. */
function commonName(lines: ReadonlyArray<GatherLine>): string {
  const counts = new Map<string, number>();
  for (const l of lines) counts.set(l.item, (counts.get(l.item) ?? 0) + 1);
  let best = lines[0]!.item;
  for (const [name, n] of counts) if (n > counts.get(best)!) best = name;
  return best;
}

/** Merges lines into rows, grouped by aisle in store order and then by item. */
export function gatherLines(lines: ReadonlyArray<GatherLine>): ReadonlyArray<GatheredRow> {
  const groups = new Map<string, Array<GatherLine>>();
  for (const line of lines) {
    const key = mergeKeyOf(line.itemKey, line.quantity, line.unit);
    const list = groups.get(key) ?? [];
    list.push(line);
    groups.set(key, list);
  }
  // Amount-less lines join a measured row for the same item, if any.
  for (const [key, list] of groups) {
    if (!key.endsWith("|none")) continue;
    const itemKey = key.slice(0, -"|none".length);
    const host = [...groups.keys()].find((k) => k !== key && k.startsWith(`${itemKey}|`));
    if (host !== undefined) {
      groups.get(host)!.push(...list);
      groups.delete(key);
    }
  }
  const rows: Array<GatheredRow> = [];
  for (const [mergeKey, list] of groups) {
    const itemKey = list[0]!.itemKey;
    const byRecipe = new Map<string, Array<GatherLine>>();
    for (const l of list) byRecipe.set(l.recipeId, [...(byRecipe.get(l.recipeId) ?? []), l]);
    rows.push({
      mergeKey,
      itemKey,
      item: commonName(list),
      ...total(list),
      aisle: aisleFor(itemKey),
      sources: [...byRecipe].map(([recipeId, own]) => ({ recipeId, ...total(own) })),
    });
  }
  return sortRows(rows);
}

/** Store order: by aisle, then alphabetically by item. */
export const sortRows = <R extends { readonly aisle: Aisle; readonly item: string }>(
  rows: ReadonlyArray<R>,
): ReadonlyArray<R> =>
  [...rows].sort(
    (a, b) =>
      AISLES.indexOf(a.aisle) - AISLES.indexOf(b.aisle) ||
      a.item.localeCompare(b.item, undefined, { sensitivity: "base" }),
  );
