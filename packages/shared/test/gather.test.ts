import { describe, expect, it } from "vite-plus/test";
import {
  aisleFor,
  AISLES,
  type ExistingGatherRow,
  type GatheredRow,
  gatherLines,
  type GatherLine,
  gatherWeek,
  ingredientKey,
  measureGroup,
  mergeKeyOf,
  parseIngredientLine,
  type PlannedEntry,
  reconcile,
  sortRows,
} from "../src/index.ts";

const line = (recipeId: string, text: string): GatherLine => {
  const p = parseIngredientLine(text);
  return {
    recipeId,
    item: p.item,
    itemKey: ingredientKey(p.item),
    quantity: p.quantity,
    unit: p.unit,
  };
};

const gather = (...entries: ReadonlyArray<readonly [string, string]>) =>
  gatherLines(entries.map(([r, t]) => line(r, t)));

const find = (rows: ReturnType<typeof gather>, itemKey: string) =>
  rows.filter((r) => r.itemKey === itemKey);

describe("measureGroup and mergeKeyOf", () => {
  it("groups measures by how they add up", () => {
    expect(measureGroup(null, null)).toBe("none");
    // A unit with no amount adds nothing, like no unit at all.
    expect(measureGroup(null, "cup")).toBe("none");
    expect(measureGroup({ min: 2, max: null }, null)).toBe("count");
    expect(measureGroup({ min: 2, max: null }, "cup")).toBe("volume");
    expect(measureGroup({ min: 2, max: null }, "tbsp")).toBe("volume");
    expect(measureGroup({ min: 2, max: null }, "g")).toBe("mass");
    expect(measureGroup({ min: 2, max: null }, "lb")).toBe("mass");
    expect(measureGroup({ min: 2, max: null }, "clove")).toBe("unit:clove");
    expect(measureGroup({ min: 2, max: null }, "can")).toBe("unit:can");
  });

  it("builds the merge key from item key and group", () => {
    expect(mergeKeyOf("flour", { min: 1, max: null }, "cup")).toBe("flour|volume");
    expect(mergeKeyOf("flour", { min: 200, max: null }, "g")).toBe("flour|mass");
    expect(mergeKeyOf("salt", null, null)).toBe("salt|none");
  });
});

describe("gatherLines merging", () => {
  it("adds the same item in the same unit", () => {
    const rows = gather(["a", "2 cups flour"], ["b", "1 cup flour"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      itemKey: "flour",
      quantity: { min: 3, max: null },
      unit: "cup",
    });
  });

  it("adds bare counts through the item key: 2 onions + 1 onion", () => {
    const rows = gather(["a", "2 onions"], ["b", "1 onion"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      itemKey: "onion",
      quantity: { min: 3, max: null },
      unit: null,
    });
  });

  it("keeps 200 g and 1 cup of flour as two rows", () => {
    const rows = gather(["a", "200 g flour"], ["b", "1 cup flour"]);
    const flour = find(rows, "flour");
    expect(flour).toHaveLength(2);
    expect(flour.map((r) => r.unit).sort((a, b) => String(a).localeCompare(String(b)))).toEqual([
      "cup",
      "g",
    ]);
    expect(flour.find((r) => r.unit === "g")!.quantity).toEqual({ min: 200, max: null });
    expect(flour.find((r) => r.unit === "cup")!.quantity).toEqual({ min: 1, max: null });
    expect(flour[0]!.mergeKey).not.toBe(flour[1]!.mergeKey);
  });

  it("keeps a bare count and a measured amount of the same item apart", () => {
    const rows = gather(["a", "2 lemons"], ["b", "1 tbsp lemon"]);
    expect(find(rows, "lemon")).toHaveLength(2);
  });

  it("sums tbsp and cup into one row in a US unit", () => {
    const rows = gather(["a", "4 tbsp olive oil"], ["b", "1 cup olive oil"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.unit).toBe("cup");
    expect(rows[0]!.quantity!.min).toBeCloseTo(1.25, 1);
    expect(rows[0]!.quantity!.max).toBeNull();
  });

  it("steps a small mixed US volume down to a unit that reads well", () => {
    const rows = gather(["a", "1 tsp vanilla extract"], ["b", "1 tbsp vanilla extract"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.unit).toBe("tbsp");
    expect(rows[0]!.quantity!.min).toBeCloseTo(1.333, 2);
  });

  it("sums g and kg into one metric row", () => {
    const rows = gather(["a", "500 g rice"], ["b", "1.5 kg rice"]);
    expect(rows).toHaveLength(1);
    // Already-metric units are kept as is, so this reads "2000 g" rather than "2 kg".
    const row = rows[0]!;
    expect(["g", "kg"]).toContain(row.unit);
    expect(row.quantity!.min * (row.unit === "kg" ? 1000 : 1)).toBeCloseTo(2000, 6);
  });

  it("sums lb and oz into a US mass", () => {
    const rows = gather(["a", "1 lb potatoes"], ["b", "8 oz potatoes"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.unit).toBe("lb");
    expect(rows[0]!.quantity!.min).toBeCloseTo(1.5, 2);
  });

  it("adds ranges, using min where max is absent", () => {
    const same = gather(["a", "1-2 tbsp maple syrup"], ["b", "1-2 tbsp maple syrup"]);
    expect(same[0]!.quantity).toEqual({ min: 2, max: 4 });
    const mixed = gather(["a", "1-2 tbsp maple syrup"], ["b", "1 tbsp maple syrup"]);
    expect(mixed[0]!.quantity).toEqual({ min: 2, max: 3 });
    const reversed = gather(["a", "1 tbsp maple syrup"], ["b", "1-3 tbsp maple syrup"]);
    expect(reversed[0]!.quantity).toEqual({ min: 2, max: 4 });
  });

  it("adds ranges through a unit conversion", () => {
    const rows = gather(["a", "1-2 cups milk"], ["b", "8 tbsp milk"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.unit).toBe("cup");
    expect(rows[0]!.quantity!.min).toBeCloseTo(1.5, 1);
    expect(rows[0]!.quantity!.max).toBeCloseTo(2.5, 1);
  });

  it("merges cloves with cloves and keeps cloves apart from cans", () => {
    const rows = gather(["a", "3 cloves garlic"], ["b", "4 cloves garlic"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ unit: "clove", quantity: { min: 7, max: null } });
    const apart = gather(["a", "3 cloves garlic"], ["b", "1 can garlic"]);
    expect(find(apart, "garlic")).toHaveLength(2);
  });

  it("keeps cloves and bare garlic apart", () => {
    const rows = gather(["a", "3 cloves garlic"], ["b", "1 garlic"]);
    expect(find(rows, "garlic")).toHaveLength(2);
  });

  it("joins a to-taste line to a measured row for the same item", () => {
    const rows = gather(["a", "1 tsp salt"], ["b", "Salt, to taste"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      itemKey: "salt",
      quantity: { min: 1, max: null },
      unit: "tsp",
    });
    expect(
      rows[0]!.sources.map((s) => s.recipeId).sort((a, b) => String(a).localeCompare(String(b))),
    ).toEqual(["a", "b"]);
    expect(rows[0]!.sources.find((s) => s.recipeId === "b")).toMatchObject({
      quantity: null,
      unit: null,
    });
  });

  it("joins a to-taste line regardless of order", () => {
    const rows = gather(["b", "Salt, to taste"], ["a", "1 tsp salt"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.quantity).toEqual({ min: 1, max: null });
  });

  it("gives a to-taste line its own row with no amount when nothing is measured", () => {
    const rows = gather(["a", "Salt, to taste"], ["b", "salt, to taste"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ quantity: null, unit: null });
    expect(rows[0]!.sources).toHaveLength(2);
  });

  it("does not join a to-taste line to a different item key", () => {
    const rows = gather(["a", "1 tsp kosher salt"], ["b", "Salt, to taste"]);
    expect(rows).toHaveLength(2);
    expect(find(rows, "salt")[0]!.quantity).toBeNull();
  });

  it("keeps a measured row when the host is one of several measure groups", () => {
    const rows = gather(["a", "1 cup flour"], ["b", "200 g flour"], ["c", "Flour, for dusting"]);
    const flour = find(rows, "flour");
    expect(flour).toHaveLength(2);
    const sourceCount = flour.reduce((n, r) => n + r.sources.length, 0);
    expect(sourceCount).toBe(3);
  });

  it("returns nothing for no lines", () => {
    expect(gatherLines([])).toEqual([]);
  });
});

describe("gatherLines sources", () => {
  it("groups per recipe with each recipe's own total", () => {
    const rows = gather(
      ["a", "1 cup flour"],
      ["b", "1/2 cup flour"],
      ["a", "1 cup flour"],
      ["c", "4 tbsp flour"],
    );
    expect(rows).toHaveLength(1);
    const [row] = rows;
    expect(row!.sources).toHaveLength(3);
    const bySource = Object.fromEntries(row!.sources.map((s) => [s.recipeId, s]));
    expect(bySource.a).toMatchObject({ unit: "cup", quantity: { min: 2, max: null } });
    expect(bySource.b).toMatchObject({ unit: "cup", quantity: { min: 0.5, max: null } });
    expect(bySource.c).toMatchObject({ unit: "tbsp", quantity: { min: 4, max: null } });
    expect(row!.unit).toBe("cup");
    expect(row!.quantity!.min).toBeCloseTo(2.75, 1);
  });

  it("totals a recipe's own mixed units for its source", () => {
    const rows = gather(["a", "1 cup milk"], ["a", "4 tbsp milk"]);
    expect(rows[0]!.sources).toHaveLength(1);
    expect(rows[0]!.sources[0]!.unit).toBe("cup");
    expect(rows[0]!.sources[0]!.quantity!.min).toBeCloseTo(1.25, 1);
  });
});

describe("gatherLines naming and order", () => {
  it("picks the most common spelling of the item", () => {
    const rows = gather(["a", "2 eggs"], ["b", "1 large egg"], ["c", "3 eggs"]);
    expect(rows).toHaveLength(1);
    expect(rows[0]!.item).toBe("eggs");
  });

  it("lets the first seen win a tie", () => {
    const rows = gather(["a", "2 large eggs"], ["b", "1 egg"]);
    expect(rows[0]!.item).toBe("large eggs");
  });

  it("sorts by aisle order, then by item name", () => {
    const rows = gather(
      ["a", "1 cup rice"],
      ["a", "2 carrots"],
      ["a", "1 tsp cumin"],
      ["a", "1 apple"],
      ["a", "1 lb chicken thighs"],
      ["a", "1 cup milk"],
      ["a", "1 loaf bread"],
      ["a", "1 frozen pizza"],
      ["a", "1 cup coffee"],
      ["a", "1 widget"],
    );
    const aisles = rows.map((r) => r.aisle);
    expect(aisles).toEqual([...aisles].sort((x, y) => AISLES.indexOf(x) - AISLES.indexOf(y)));
    expect(new Set(aisles).size).toBeGreaterThanOrEqual(8);
    const produce = rows.filter((r) => r.aisle === "produce").map((r) => r.item);
    expect(produce).toEqual([...produce].sort((x, y) => x.localeCompare(y)));
    expect(produce.slice(0, 2)).toEqual(["apple", "carrots"]);
  });

  it("sorts item names case-insensitively", () => {
    const rows = sortRows([
      { aisle: "pantry" as const, item: "Sugar" },
      { aisle: "pantry" as const, item: "flour" },
      { aisle: "produce" as const, item: "zucchini" },
      { aisle: "pantry" as const, item: "Baking soda" },
    ]);
    expect(rows.map((r) => r.item)).toEqual(["zucchini", "Baking soda", "flour", "Sugar"]);
  });

  it("doesn't mutate the rows it sorts", () => {
    const input = [
      { aisle: "pantry" as const, item: "b" },
      { aisle: "produce" as const, item: "a" },
    ];
    sortRows(input);
    expect(input[0]!.item).toBe("b");
  });
});

describe("gatherWeek", () => {
  const planned = (
    recipeId: string,
    recipeServings: number | null,
    servings: number | null,
    ...texts: ReadonlyArray<string>
  ): PlannedEntry => ({
    recipeId,
    recipeServings,
    servings,
    ingredients: texts.map((t) => {
      const { recipeId: _, ...rest } = line(recipeId, t);
      return rest;
    }),
  });

  it("scales each entry by its servings against the recipe's", () => {
    const rows = gatherWeek([planned("a", 4, 8, "1 cup flour", "1-2 eggs")]);
    expect(find(rows, "flour")[0]!.quantity).toEqual({ min: 2, max: null });
    expect(find(rows, "egg")[0]!.quantity).toEqual({ min: 2, max: 4 });
  });

  it("leaves an entry unscaled when either serving count is unknown", () => {
    const rows = gatherWeek([
      planned("a", null, 8, "1 cup flour"),
      planned("b", 4, null, "100 g sugar"),
    ]);
    expect(find(rows, "flour")[0]!.quantity).toEqual({ min: 1, max: null });
    expect(find(rows, "sugar")[0]!.quantity).toEqual({ min: 100, max: null });
  });

  it("sums a recipe planned twice into one source, and keeps amount-less lines bare", () => {
    const rows = gatherWeek([
      planned("a", 2, 2, "1 cup milk", "salt"),
      planned("a", 2, 4, "1 cup milk", "salt"),
    ]);
    const milk = find(rows, "milk")[0]!;
    expect(milk.quantity).toEqual({ min: 3, max: null });
    expect(milk.sources).toEqual([{ recipeId: "a", quantity: { min: 3, max: null }, unit: "cup" }]);
    expect(find(rows, "salt")[0]!.quantity).toBeNull();
  });

  it("returns nothing for an empty week", () => {
    expect(gatherWeek([])).toEqual([]);
  });
});

describe("reconcile", () => {
  /** Storage's rounding: numeric(12, 4). */
  const round = (n: number) => Math.round(n * 10_000) / 10_000;

  /** A row as the list holds it after a previous sync. */
  const held = (
    id: string,
    row: GatheredRow,
    extra: Partial<ExistingGatherRow> = {},
  ): ExistingGatherRow => ({
    id,
    item: row.item,
    itemKey: row.itemKey,
    quantity: row.quantity,
    unit: row.unit,
    aisle: row.aisle,
    checked: false,
    sources: row.sources,
    ...extra,
  });

  it("changes nothing when the week is the same", () => {
    const rows = gather(["a", "200 g spaghetti"], ["a", "2 eggs"], ["b", "2 eggs"]);
    const existing = rows.map((r, i) => held(`id${i}`, r, { checked: i === 0 }));
    expect(reconcile(existing, rows, round)).toEqual({ inserts: [], updates: [], removals: [] });
  });

  it("adds rows that are new and removes leftovers", () => {
    const [eggs] = gather(["a", "2 eggs"]);
    const [lettuce] = gather(["b", "2 lettuce"]);
    const [rice] = gather(["c", "1 cup rice"]);
    const { inserts, updates, removals } = reconcile(
      [held("eggs", eggs!), held("lettuce", lettuce!)],
      [eggs!, rice!],
      round,
    );
    expect(inserts).toEqual([rice]);
    expect(updates).toEqual([]);
    expect(removals).toEqual(["lettuce"]);
  });

  it("unchecks a checked row when the week needs more", () => {
    const [before] = gather(["a", "1 cup flour"]);
    const [after] = gather(["a", "2 cups flour"]);
    const { updates } = reconcile([held("flour", before!, { checked: true })], [after!], round);
    expect(updates).toEqual([
      { id: "flour", row: after, changed: true, uncheck: true, sources: true },
    ]);
  });

  it("unchecks when another recipe adds to a checked row", () => {
    const [before] = gather(["a", "2 eggs"]);
    const [after] = gather(["a", "2 eggs"], ["b", "3 eggs"]);
    const { updates } = reconcile([held("eggs", before!, { checked: true })], [after!], round);
    expect(updates).toEqual([
      { id: "eggs", row: after, changed: true, uncheck: true, sources: true },
    ]);
  });

  it("counts more through a unit change: 1 cup to 20 tbsp is more", () => {
    const [before] = gather(["a", "1 cup milk"]);
    const [after] = gather(["a", "20 tbsp milk"]);
    const { updates } = reconcile([held("milk", before!, { checked: true })], [after!], round);
    expect(updates[0]).toMatchObject({ changed: true, uncheck: true });
  });

  it("keeps the check when the week needs less", () => {
    const [before] = gather(["a", "2 cups flour"]);
    const [after] = gather(["a", "1.5 cups flour"]);
    const { updates } = reconcile([held("flour", before!, { checked: true })], [after!], round);
    expect(updates).toEqual([
      { id: "flour", row: after, changed: true, uncheck: false, sources: true },
    ]);
  });

  it("never unchecks a row that isn't checked", () => {
    const [before] = gather(["a", "1 cup flour"]);
    const [after] = gather(["a", "2 cups flour"]);
    const { updates } = reconcile([held("flour", before!)], [after!], round);
    expect(updates[0]).toMatchObject({ changed: true, uncheck: false });
  });

  it("updates a row whose name, unit or aisle changed but whose amount didn't", () => {
    const [row] = gather(["a", "2 eggs"]);
    for (const extra of [{ item: "large eggs" }, { aisle: null }, { aisle: "pantry" }]) {
      const { updates } = reconcile(
        [held("eggs", row!, { checked: true, ...extra })],
        [row!],
        round,
      );
      expect(updates).toEqual([{ id: "eggs", row, changed: true, uncheck: false, sources: false }]);
    }
    const [cups] = gather(["a", "1 cup milk"]);
    const { updates } = reconcile([held("milk", cups!, { unit: "ml" })], [cups!], round);
    expect(updates[0]).toMatchObject({ changed: true, sources: false });
  });

  it("rewrites only the sources when the total holds but who needs it moved", () => {
    const [before] = gather(["a", "2 eggs"], ["b", "2 eggs"]);
    const [after] = gather(["c", "4 eggs"]);
    const { updates } = reconcile([held("eggs", before!, { checked: true })], [after!], round);
    expect(updates).toEqual([
      { id: "eggs", row: after, changed: false, uncheck: false, sources: true },
    ]);
  });

  it("matches sources whatever order they were read in", () => {
    const [row] = gather(["a", "2 eggs"], ["b", "3 eggs"]);
    const existing = held("eggs", row!, { sources: [...row!.sources].reverse() });
    expect(reconcile([existing], [row!], round).updates).toEqual([]);
  });

  it("keeps the first row for a merge key and removes any that repeat it", () => {
    const [eggs] = gather(["a", "2 eggs"]);
    const { inserts, updates, removals } = reconcile(
      [held("first", eggs!, { checked: true }), held("again", eggs!), held("third", eggs!)],
      [eggs!],
      round,
    );
    expect(inserts).toEqual([]);
    expect(updates).toEqual([]);
    expect(removals).toEqual(["again", "third"]);
  });

  it("keys rows by measure, so cups and grams of one item are two rows", () => {
    const rows = gather(["a", "1 cup flour"], ["b", "200 g flour"]);
    const [cups] = rows.filter((r) => r.unit === "cup");
    const { inserts, removals } = reconcile([held("cups", cups!)], rows, round);
    expect(inserts.map((r) => r.unit)).toEqual(["g"]);
    expect(removals).toEqual([]);
  });

  it("compares amounts as stored, so a third doesn't flap on every sync", () => {
    const rows = gatherWeek([
      {
        recipeId: "a",
        recipeServings: 6,
        servings: 2,
        ingredients: [
          { item: "flour", itemKey: "flour", quantity: { min: 1, max: null }, unit: "cup" },
          { item: "onion", itemKey: "onion", quantity: { min: 1, max: null }, unit: null },
        ],
      },
    ]);
    const first = reconcile([], rows, round);
    expect(first.inserts.map((r) => r.quantity)).toEqual([
      { min: 0.3333, max: null },
      { min: 0.3333, max: null },
    ]);
    expect(first.inserts[0]!.sources[0]!.quantity).toEqual({ min: 0.3333, max: null });
    // Stored rounded down, checked: the next sync wants 1/3 again and leaves it be.
    const existing = first.inserts.map((r, i) => held(`id${i}`, r, { checked: true }));
    expect(reconcile(existing, rows, round)).toEqual({ inserts: [], updates: [], removals: [] });
  });
});

describe("aisleFor", () => {
  const cases: ReadonlyArray<readonly [string, string]> = [
    ["garlic powder", "spices"],
    ["onion powder", "spices"],
    ["freshly ground pepper", "spices"],
    ["cream of tartar", "spices"],
    ["apple cider vinegar", "pantry"],
    ["coconut cream", "pantry"],
    ["egg noodles", "pantry"],
    ["orange juice", "drinks"],
    ["garlic cloves", "produce"],
    ["onion", "produce"],
    ["2 red onions", "produce"],
    ["garlic", "produce"],
    ["fresh ginger", "produce"],
    ["cherry tomatoes", "produce"],
    ["red bell pepper", "produce"],
    ["jalapeno", "produce"],
    ["eggplant", "produce"],
    ["aubergine", "produce"],
    ["baby spinach", "produce"],
    ["fresh basil", "produce"],
    ["lemons", "produce"],
    ["sweet potatoes", "produce"],
    ["chicken thighs", "meat"],
    ["chicken breast", "meat"],
    ["ground beef", "meat"],
    ["salmon fillets", "meat"],
    ["bacon", "meat"],
    ["milk", "dairy"],
    ["large eggs", "dairy"],
    ["unsalted butter", "dairy"],
    ["greek yogurt", "dairy"],
    ["crumbled feta", "dairy"],
    ["sour cream", "dairy"],
    ["baguette", "bakery"],
    ["flour tortillas", "bakery"],
    ["chicken stock", "pantry"],
    ["vegetable broth", "pantry"],
    ["crushed tomatoes", "pantry"],
    ["tomato paste", "pantry"],
    ["olive oil", "pantry"],
    ["all-purpose flour", "pantry"],
    ["brown sugar", "pantry"],
    ["canned chickpeas", "pantry"],
    ["peanut butter", "pantry"],
    ["black pepper", "spices"],
    ["chili flakes", "spices"],
    ["red pepper flakes", "spices"],
    ["kosher salt", "spices"],
    ["ground cumin", "spices"],
    ["smoked paprika", "spices"],
    ["bay leaves", "spices"],
    ["dried oregano", "spices"],
    ["frozen peas", "frozen"],
    ["ice cream", "frozen"],
    ["sparkling water", "drinks"],
    ["white wine", "drinks"],
    ["xanthan gum", "other"],
    ["", "other"],
  ];
  it.each(cases)("%s is in %s", (text, aisle) => {
    expect(aisleFor(ingredientKey(text))).toBe(aisle);
  });

  it("is never dairy for eggplant, and keeps pepper kinds apart", () => {
    expect(aisleFor(ingredientKey("eggplant"))).not.toBe("dairy");
    expect(aisleFor(ingredientKey("black pepper"))).not.toBe(
      aisleFor(ingredientKey("red bell pepper")),
    );
  });
});
