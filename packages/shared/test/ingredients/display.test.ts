import { describe, expect, it } from "vite-plus/test";
import { displayMeasure, type UnitCode, type UnitSystemChoice } from "../../src/index.ts";

// Known conversions and scalings, as the recipe view shows them (#10).
const table: ReadonlyArray<
  readonly [
    readonly [number, number | null],
    UnitCode | null,
    number,
    UnitSystemChoice,
    string,
    string | null,
  ]
> = [
  // As written, scaled.
  [[1, null], "cup", 2, "asWritten", "2", "c"],
  [[0.5, null], "cup", 0.25, "asWritten", "2", "tbsp"],
  [[1, null], "tsp", 0.25, "asWritten", "¼", "tsp"],
  [[350, null], "g", 2, "asWritten", "700", "g"],
  [[3, null], "clove", 1.5, "asWritten", "4 ½", "cloves"],
  [[2, 3], "tbsp", 2, "asWritten", "4–6", "tbsp"],
  [[2, null], null, 1.5, "asWritten", "3", null],
  [[1, null], "tsp", 1 / 32, "asWritten", "pinch", null],
  // US to metric, rounded to what a scale or jug shows.
  [[1, null], "cup", 1, "metric", "235", "ml"],
  [[1, null], "tbsp", 1, "metric", "15", "ml"],
  [[1, null], "tsp", 1, "metric", "5", "ml"],
  [[2, 3], "tbsp", 2, "metric", "59–89", "ml"],
  [[1, null], "fl_oz", 1, "metric", "30", "ml"],
  [[4, null], "cup", 1, "metric", "945", "ml"],
  [[5, null], "cup", 1, "metric", "1.19", "l"],
  [[1, null], "lb", 1, "metric", "455", "g"],
  [[14, null], "oz", 1, "metric", "395", "g"],
  [[3, null], "lb", 1, "metric", "1.36", "kg"],
  // Metric to US.
  [[250, null], "ml", 1, "us", "1", "c"],
  [[1, null], "l", 1, "us", "1", "qt"],
  [[15, null], "ml", 1, "us", "1", "tbsp"],
  [[500, null], "g", 1, "us", "1 ⅛", "lb"],
  [[100, null], "g", 1, "us", "3 ½", "oz"],
  [[1.5, null], "kg", 1, "us", "3 ⅓", "lb"],
  // Scaled metric amounts round too, and step between g and kg.
  [[7, null], "g", 1 / 3, "asWritten", "2.5", "g"],
  [[15, null], "g", 1.25, "asWritten", "19", "g"],
  [[250, null], "ml", 0.75, "metric", "190", "ml"],
  [[2, null], "kg", 1 / 3, "metric", "665", "g"],
  [[2, null], "kg", 1 / 3, "asWritten", "665", "g"],
  [[600, null], "g", 2, "asWritten", "1.2", "kg"],
  [[4.225, null], "cup", 1, "metric", "1", "l"],
  [[1, null], "tsp", 1 / 32, "metric", "pinch", null],
  // Already in the target system, or not convertible.
  [[200, null], "g", 1, "metric", "200", "g"],
  [[2, null], "cup", 1, "us", "2", "c"],
  [[3, null], "clove", 1, "metric", "3", "cloves"],
  [[1, null], "pinch", 2, "metric", "2", "pinches"],
  [[1, null], "can", 2, "us", "2", "cans"],
];

describe("displayMeasure", () => {
  it.each(table)("%j %s ×%d %s → %s %s", ([min, max], unit, factor, system, amount, label) => {
    expect(displayMeasure({ min, max }, unit, factor, system)).toEqual({ amount, unit: label });
  });
});
