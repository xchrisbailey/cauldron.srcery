import { copy, detectTimer, parseIngredientLine, Recipe } from "@cauldron/shared";
import { Schema } from "effect";
import { describe, expect, it } from "vite-plus/test";
import {
  decodeRecipeForm,
  emptyRecipeForm,
  fromDraft,
  fromRecipe,
  ingredientRow,
  parseQuantity,
  splitIngredientPaste,
  splitStepPaste,
  stepRow,
  toRecipeInput,
  validateRecipeForm,
  type IngredientRow,
  type RecipeFormValues,
} from "../src/lib/recipe-form.ts";

const { validation } = copy;

const BLOCK = `
• 2 tbsp olive oil
• ½ cup chopped onion

- 3 cloves garlic, minced
* 1 lb ground beef
▢ 1 1/2 cups all-purpose flour

For the sauce:
1 (14 oz) can crushed tomatoes
2-3 tbsp sugar
1 tsp dried oregano
Salt and pepper, to taste
2 large eggs
1/4 cup grated parmesan
1 cup water
`;

const form = (patch: Partial<RecipeFormValues> = {}): RecipeFormValues => ({
  ...emptyRecipeForm(),
  title: "Soup",
  ...patch,
});

describe("splitIngredientPaste + ingredientRow", () => {
  const lines = splitIngredientPaste(BLOCK);
  const rows = lines.map((line) => ingredientRow(line));

  it("drops bullets and blank lines", () => {
    expect(lines).toHaveLength(13);
    expect(lines[0]).toBe("2 tbsp olive oil");
    expect(lines[1]).toBe("½ cup chopped onion");
    expect(lines.every((l) => !/^[-•*▢]/.test(l))).toBe(true);
  });

  it("makes one heading row and the rest line rows", () => {
    const headings = rows.filter((r) => r.kind === "heading");
    expect(headings).toHaveLength(1);
    expect(headings[0]!.text).toBe("For the sauce");
    expect(rows.filter((r) => r.kind === "line")).toHaveLength(12);
  });

  it("parses lines to quantity, unit and item", () => {
    const byText = (t: string) =>
      rows.find((r): r is IngredientRow => r.kind === "line" && r.text === t)!.parsed;
    expect(byText("2 tbsp olive oil")).toMatchObject({
      quantity: { min: 2, max: null },
      unit: "tbsp",
      item: "olive oil",
    });
    expect(byText("½ cup chopped onion")).toMatchObject({
      quantity: { min: 0.5, max: null },
      unit: "cup",
      item: "chopped onion",
    });
    expect(byText("1 1/2 cups all-purpose flour")).toMatchObject({
      quantity: { min: 1.5, max: null },
      unit: "cup",
    });
    expect(byText("3 cloves garlic, minced")).toMatchObject({
      quantity: { min: 3, max: null },
      unit: "clove",
      item: "garlic",
      note: "minced",
    });
    expect(byText("1 (14 oz) can crushed tomatoes")).toMatchObject({
      quantity: { min: 1, max: null },
      unit: "can",
      item: "crushed tomatoes",
      alt: { quantity: { min: 14, max: null }, unit: "oz" },
    });
    expect(byText("2-3 tbsp sugar").quantity).toEqual({ min: 2, max: 3 });
    expect(byText("Salt and pepper, to taste")).toMatchObject({
      quantity: null,
      unit: null,
      item: "Salt and pepper",
      note: "to taste",
    });
  });

  it("parses most lines with a quantity and a unit or item", () => {
    const lineRows = rows.filter((r): r is IngredientRow => r.kind === "line");
    const good = lineRows.filter((r) => r.parsed.quantity !== null && r.parsed.item !== "");
    expect(good.length / lineRows.length).toBeGreaterThanOrEqual(0.8);
  });

  it("carries the flag and starts uncorrected", () => {
    const row = ingredientRow("1 cup rice", "check this");
    expect(row).toMatchObject({ kind: "line", corrected: false, flag: "check this" });
  });
});

describe("splitStepPaste", () => {
  it("strips numbers and 'Step N:' prefixes, one step per line", () => {
    expect(splitStepPaste("1. Chop the onion.\n2) Fry it.\nStep 3: Serve.\nstep 4 - Eat.")).toEqual(
      ["Chop the onion.", "Fry it.", "Serve.", "- Eat."],
    );
  });

  it("joins wrapped lines inside blank-line separated paragraphs", () => {
    const pasted =
      "1. Chop the onion\nfinely and set aside.\n\n2. Fry the onion\nuntil golden.\n\n\nServe hot.";
    expect(splitStepPaste(pasted)).toEqual([
      "Chop the onion finely and set aside.",
      "Fry the onion until golden.",
      "Serve hot.",
    ]);
  });

  it("strips bullets", () => {
    expect(splitStepPaste("- Mix\n• Bake\n* Cool")).toEqual(["Mix", "Bake", "Cool"]);
  });

  it("handles CRLF and empty input", () => {
    expect(splitStepPaste("1. A\r\n\r\n2. B")).toEqual(["A", "B"]);
    expect(splitStepPaste("  \n ")).toEqual([]);
  });
});

describe("toRecipeInput", () => {
  const values = form({
    servings: " 4 ",
    prepMinutes: "10",
    cookMinutes: "",
    totalMinutes: "30",
    sourceUrl: "   ",
    description: "Warm",
    ingredients: [
      ingredientRow("1 cup rice"),
      ingredientRow(""),
      ingredientRow("For the sauce:"),
      ingredientRow("2 tbsp butter"),
      ingredientRow("   "),
      ingredientRow("1 tsp salt"),
    ],
    steps: [stepRow("Boil the rice for 10 minutes."), stepRow(""), stepRow("Serve.")],
  });
  const { input, rowOf, stepOf } = toRecipeInput(values);

  it("turns headings into the section of following lines", () => {
    expect(input.ingredients.map((i) => [i.item, i.section])).toEqual([
      ["rice", null],
      ["butter", "For the sauce"],
      ["salt", "For the sauce"],
    ]);
    expect(input.ingredients[1]).toMatchObject({ original: "2 tbsp butter" });
  });

  it("drops blank rows and steps and maps indexes back to the form", () => {
    expect(rowOf).toEqual([0, 3, 5]);
    expect(stepOf).toEqual([0, 2]);
    expect(input.steps).toHaveLength(2);
    expect(input.steps[0]).toMatchObject({ timerSeconds: 600 });
  });

  it("maps blank sourceUrl to null and number fields to numbers or null", () => {
    expect(input.sourceUrl).toBeNull();
    expect(input.servings).toBe(4);
    expect(input.prepMinutes).toBe(10);
    expect(input.cookMinutes).toBeNull();
    expect(input.totalMinutes).toBe(30);
  });

  it("sends macros as numbers, blanks as null", () => {
    const { input } = toRecipeInput(
      form({ macros: { calories: "520", protein: " 31.5 ", carbs: "", fat: "18" } }),
    );
    expect(input.macros).toEqual({ calories: 520, protein: 31.5, carbs: null, fat: 18 });
  });

  it("flags a macro that isn't a number on its own field", () => {
    const errors = validateRecipeForm(
      form({ title: "Soup", macros: { calories: "lots", protein: "", carbs: "", fat: "-2" } }),
    );
    expect(errors["macros.calories"]).toBeDefined();
    expect(errors["macros.fat"]).toBeDefined();
    expect(errors["macros.protein"]).toBeUndefined();
  });

  it("keeps a real source URL", () => {
    expect(toRecipeInput(form({ sourceUrl: "https://example.com/r" })).input.sourceUrl).toBe(
      "https://example.com/r",
    );
  });

  it("a heading with no text clears the section", () => {
    const r = toRecipeInput(
      form({
        ingredients: [
          { key: "h", kind: "heading", text: "A", flag: null },
          ingredientRow("1 cup rice"),
          { key: "h2", kind: "heading", text: "  ", flag: null },
          ingredientRow("1 cup oats"),
        ],
      }),
    );
    expect(r.input.ingredients.map((i) => i.section)).toEqual(["A", null]);
  });
});

describe("validateRecipeForm", () => {
  const valid = () =>
    form({
      servings: "4",
      sourceUrl: "https://example.com",
      ingredients: [ingredientRow("1 cup rice")],
      steps: [stepRow("Cook it.")],
    });

  it("is empty for a valid form", () => {
    expect(validateRecipeForm(valid())).toEqual({});
  });

  it("the blank starter form only fails on the title", () => {
    expect(Object.keys(validateRecipeForm(emptyRecipeForm()))).toEqual(["title"]);
  });

  it("flags an empty title", () => {
    expect(validateRecipeForm({ ...valid(), title: "  " }).title).toBe(validation.required.text);
  });

  it("flags servings that aren't whole numbers", () => {
    const whole = validation.wholeNumber(1, 1000).text;
    expect(validateRecipeForm({ ...valid(), servings: "ten" }).servings).toBe(whole);
    expect(validateRecipeForm({ ...valid(), servings: "2.5" }).servings).toBe(whole);
    expect(validateRecipeForm({ ...valid(), servings: "0" }).servings).toBe(whole);
  });

  it("flags a bad source URL", () => {
    expect(validateRecipeForm({ ...valid(), sourceUrl: "not a url" }).sourceUrl).toBe(
      validation.link.text,
    );
    expect(validateRecipeForm({ ...valid(), sourceUrl: "ftp://example.com" }).sourceUrl).toBe(
      validation.link.text,
    );
  });

  it("reports an ingredient with no item under its form row index, past a heading", () => {
    const base = ingredientRow("1 cup rice") as IngredientRow;
    const noItem: IngredientRow = {
      ...base,
      text: "2 cups",
      parsed: { ...base.parsed, item: "", original: "2 cups" },
      corrected: true,
    };
    const errors = validateRecipeForm({
      ...valid(),
      ingredients: [ingredientRow("For the sauce:"), ingredientRow("1 tsp salt"), noItem],
    });
    expect(errors).toEqual({ "ingredients[2]": validation.required.text });
  });

  it("an empty step is dropped, not an error", () => {
    expect(validateRecipeForm({ ...valid(), steps: [stepRow(""), stepRow("Cook it.")] })).toEqual(
      {},
    );
  });

  it("reports a bad step timer under steps[<form index>]", () => {
    const errors = validateRecipeForm({
      ...valid(),
      steps: [stepRow(""), { ...stepRow("Cook it."), timerSeconds: 0, timerSet: true }],
    });
    expect(Object.keys(errors)).toEqual(["steps[1]"]);
  });
});

describe("decodeRecipeForm", () => {
  it("is null when invalid", () => {
    expect(decodeRecipeForm(emptyRecipeForm())).toBeNull();
    expect(decodeRecipeForm(form({ servings: "x" }))).toBeNull();
  });

  it("returns the trimmed RecipeInput when valid", () => {
    const input = decodeRecipeForm(
      form({
        title: "  Soup  ",
        servings: "2",
        ingredients: [ingredientRow("1 cup rice")],
        steps: [stepRow("Cook.")],
      }),
    );
    expect(input).not.toBeNull();
    expect(input!.title).toBe("Soup");
    expect(input!.servings).toBe(2);
    expect(input!.ingredients[0]!.item).toBe("rice");
    expect(input!.steps[0]!.text).toBe("Cook.");
  });
});

describe("fromRecipe round trip", () => {
  const id = "8f0c2a4e-1b6d-4c1e-9a53-0d2f6b7a9c11";
  const parsedRice = parseIngredientLine("1 cup rice");
  const parsedButter = parseIngredientLine("2 tbsp butter");
  const data = {
    id,
    title: "Rice",
    description: "Plain",
    servings: 4,
    prepMinutes: 5,
    cookMinutes: 20,
    totalMinutes: 25,
    photoKey: null,
    macros: { calories: 410, protein: 8.5, carbs: null, fat: 12 },
    tags: [{ id: "1a2b3c4d-1b6d-4c1e-9a53-0d2f6b7a9c11", name: "dinner", kind: "meal" }],
    lastCookedOn: null,
    createdAt: new Date("2026-01-01T00:00:00Z"),
    updatedAt: new Date("2026-01-02T00:00:00Z"),
    sourcePlatform: "web",
    sourceUrl: "https://example.com/rice",
    sourceAuthor: "Ann",
    notes: "Rinse first.",
    ingredients: [
      { ...parsedRice, section: null, itemKey: "rice" },
      // Stored item differs from what the parser reads from `original`.
      {
        ...parsedButter,
        item: "salted butter",
        section: "For the sauce",
        itemKey: "salted butter",
      },
    ],
    steps: [
      { section: null, text: "Boil for 10 minutes.", timerSeconds: 600 },
      { section: "Sauce", text: "Melt the butter for 2 minutes.", timerSeconds: 90 },
      { section: null, text: "Serve.", timerSeconds: 30 },
    ],
    deletedAt: null,
  };
  const recipe = Schema.decodeUnknownSync(Recipe)(data);
  const values = fromRecipe(recipe);

  it("builds a heading row before each new section", () => {
    expect(values.ingredients.map((r) => r.kind)).toEqual(["line", "heading", "line"]);
    expect(values.ingredients[1]!.text).toBe("For the sauce");
  });

  it("round trips to the recipe's data", () => {
    const { input } = toRecipeInput(values);
    expect(input.title).toBe("Rice");
    expect(input.description).toBe("Plain");
    expect(input.servings).toBe(4);
    expect(input.prepMinutes).toBe(5);
    expect(input.cookMinutes).toBe(20);
    expect(input.totalMinutes).toBe(25);
    expect(input.macros).toEqual({ calories: 410, protein: 8.5, carbs: null, fat: 12 });
    expect(input.sourcePlatform).toBe("web");
    expect(input.sourceUrl).toBe("https://example.com/rice");
    expect(input.sourceAuthor).toBe("Ann");
    expect(input.notes).toBe("Rinse first.");
    expect(input.tags).toEqual(["dinner"]);
    expect(input.ingredients).toEqual(recipe.ingredients.map(({ itemKey: _k, ...rest }) => rest));
    expect(input.steps).toEqual(recipe.steps);
    expect(validateRecipeForm(values)).toEqual({});
  });

  it("marks only the corrected ingredient as corrected", () => {
    const lines = values.ingredients.filter((r): r is IngredientRow => r.kind === "line");
    expect(lines.map((r) => r.corrected)).toEqual([false, true]);
    expect(lines[1]!.parsed.item).toBe("salted butter");
  });

  it("sets timerSet only when the timer differs from the text", () => {
    expect(values.steps.map((s) => s.timerSet)).toEqual([
      detectTimer("Boil for 10 minutes.") !== 600,
      true,
      true,
    ]);
    expect(values.steps[0]!.timerSet).toBe(false);
    expect(values.steps[1]!.section).toBe("Sauce");
  });

  it("falls back to one blank row each for an empty recipe", () => {
    const empty = fromRecipe(
      Schema.decodeUnknownSync(Recipe)({ ...data, ingredients: [], steps: [] }),
    );
    expect(empty.ingredients).toHaveLength(1);
    expect(empty.steps).toHaveLength(1);
  });
});

describe("parseQuantity", () => {
  it("reads mixed numbers, ranges and vulgar fractions", () => {
    expect(parseQuantity("1 1/2")).toEqual({ min: 1.5, max: null });
    expect(parseQuantity("2-3")).toEqual({ min: 2, max: 3 });
    expect(parseQuantity("½")).toEqual({ min: 0.5, max: null });
    expect(parseQuantity("3")).toEqual({ min: 3, max: null });
  });

  it("is null when blank and 'invalid' for junk", () => {
    expect(parseQuantity("")).toBeNull();
    expect(parseQuantity("   ")).toBeNull();
    expect(parseQuantity("abc")).toBe("invalid");
  });
});

describe("fromDraft", () => {
  const draft = {
    title: "Dal",
    description: null,
    servings: 4,
    prepMinutes: null,
    cookMinutes: 30,
    totalMinutes: null,
    sourcePlatform: "web" as const,
    sourceUrl: "https://example.com/dal",
    sourceAuthor: "Ada",
    siteName: "Example",
    notes: null,
    photoKey: null,
    tags: ["Indian"],
    ingredients: [
      { line: "1 cup red lentils", section: null, unsure: false },
      { line: "2 tsp cumin seeds", section: "For the tarka", unsure: true },
    ],
    steps: [{ text: "Simmer for 25 minutes.", section: null, unsure: false }],
    unsure: ["servings" as const],
  };

  it("reads every line with the shared parser and flags what the import wasn't sure of", () => {
    const form = fromDraft(draft);
    expect(form).toMatchObject({
      title: "Dal",
      servings: "4",
      cookMinutes: "30",
      sourceUrl: "https://example.com/dal",
      sourcePlatform: "web",
      sourceAuthor: "Ada",
      review: ["servings"],
    });
    expect(form.ingredients.map((row) => [row.kind, row.text, row.flag])).toEqual([
      ["line", "1 cup red lentils", null],
      ["heading", "For the tarka", null],
      ["line", "2 tsp cumin seeds", copy.imports.unsureLine.text],
    ]);
    const line = form.ingredients[0] as IngredientRow;
    expect(line.parsed).toEqual(parseIngredientLine("1 cup red lentils"));
    expect(form.steps[0]).toMatchObject({ text: "Simmer for 25 minutes.", timerSeconds: 1500 });
  });

  it("decodes to the recipe it would save, source included", () => {
    expect(decodeRecipeForm(fromDraft(draft))).toMatchObject({
      sourcePlatform: "web",
      sourceUrl: "https://example.com/dal",
      ingredients: [
        { item: "red lentils", section: null },
        { item: "cumin seeds", section: "For the tarka" },
      ],
    });
  });
});
