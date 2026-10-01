import { describe, expect, it } from "vite-plus/test";
import {
  aisleFor,
  AISLES,
  gatherLines,
  type GatherLine,
  ingredientKey,
  measureGroup,
  mergeKeyOf,
  parseIngredientLine,
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

describe("aisleFor", () => {
  const cases: ReadonlyArray<readonly [string, string]> = [
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
