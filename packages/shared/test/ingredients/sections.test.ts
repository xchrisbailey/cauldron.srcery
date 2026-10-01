import { describe, expect, it } from "vite-plus/test";
import { readHeading, readIngredientBlock, withHeadings } from "../../src/index.ts";

// One heading rule for every way lines come in: typed or pasted into the
// editor, read from a pasted or imported recipe, and written in the seeds.

describe("readHeading", () => {
  describe("headings", () => {
    it.each([
      // Typed or pasted into the editor.
      ["For the sauce:", "For the sauce"],
      ["For the crust", "For the crust"],
      ["Dressing:", "Dressing"],
      ["- FOR THE FILLING", "FOR THE FILLING"],
      ["▢ For the crust:", "For the crust"],
      ["  To serve:  ", "To serve"],
      // Pasted from notes, blogs and captions.
      ["**Dressing:**", "Dressing"],
      ["_Topping_:", "Topping"],
      ["🥗 For the salad", "For the salad"],
      ["• For the glaze:", "For the glaze"],
      // Markdown, as the seeds write them.
      ["## To serve", "To serve"],
      ["# Sauce", "Sauce"],
      ["### For the sauce:", "For the sauce"],
    ])("%j reads as %j", (line, heading) => {
      expect(readHeading(line)).toBe(heading);
    });
  });

  describe("ingredients and blanks", () => {
    it.each([
      "2 cups flour",
      "Salt, to taste",
      "Kosher salt",
      "1 (14 oz) can crushed tomatoes",
      // Colon lines with a quantity are ingredients, digits or not.
      "One onion:",
      "A pinch:",
      "200 g feta:",
      // Hashtags and empty markdown aren't headings.
      "#vegan",
      "## ",
      "",
      "   ",
    ])("%j", (line) => {
      expect(readHeading(line)).toBeNull();
    });
  });
});

describe("readIngredientBlock", () => {
  it("gives each line the heading above it and drops headings and blanks", () => {
    const block = readIngredientBlock([
      "1 cup rice",
      "",
      "For the sauce:",
      "  2 tbsp butter  ",
      "1 tsp salt",
      "## To serve",
      "Parsley",
    ]);
    expect(block.map((i) => [i.original, i.item, i.section])).toEqual([
      ["1 cup rice", "rice", null],
      ["2 tbsp butter", "butter", "For the sauce"],
      ["1 tsp salt", "salt", "For the sauce"],
      ["Parsley", "Parsley", "To serve"],
    ]);
    expect(block[1]).toMatchObject({ quantity: { min: 2, max: null }, unit: "tbsp" });
  });

  it("is empty for no lines or only headings", () => {
    expect(readIngredientBlock([])).toEqual([]);
    expect(readIngredientBlock(["For the sauce:", ""])).toEqual([]);
  });
});

describe("withHeadings", () => {
  const line = (item: string, section: string | null) => ({ item, section });

  it("puts a heading before each new section, none before unsectioned lines", () => {
    const rows = withHeadings([
      line("rice", null),
      line("butter", "For the sauce"),
      line("salt", "For the sauce"),
      line("water", null),
      line("parsley", "To serve"),
    ]);
    expect(rows.map((r) => (r.kind === "heading" ? `# ${r.text}` : r.line.item))).toEqual([
      "rice",
      "# For the sauce",
      "butter",
      "salt",
      "water",
      "# To serve",
      "parsley",
    ]);
  });

  it("round trips with readIngredientBlock", () => {
    const lines = ["1 cup rice", "For the sauce", "2 tbsp butter", "For serving", "Parsley"];
    const text = withHeadings(readIngredientBlock(lines)).map((r) =>
      r.kind === "heading" ? r.text : r.line.original,
    );
    expect(text).toEqual(lines);
  });
});
