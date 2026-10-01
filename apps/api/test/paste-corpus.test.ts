import { readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vite-plus/test";
import { readRecipeText } from "../src/imports/textRecipe.ts";

// Messy recipes people paste from notes apps, emails, chats, PDFs and blogs.
// Each NN-name.txt has an NN-name.json holding the expected reading. Fixtures
// marked needsModel have no headings, so only the model reads them reliably:
// the reader must not call them clear, which sends them to the model.

interface Expected {
  title: string;
  ingredients: Array<string>;
  steps: Array<string>;
  sections?: Record<string, string>;
  servings?: number;
  needsModel?: true;
}

const dir = new URL("./fixtures/paste/", import.meta.url);
const names = readdirSync(dir)
  .filter((f) => f.endsWith(".txt"))
  .map((f) => f.slice(0, -4))
  .toSorted();

const load = (name: string) => ({
  text: readFileSync(new URL(`${name}.txt`, dir), "utf8"),
  expected: JSON.parse(readFileSync(new URL(`${name}.json`, dir), "utf8")) as Expected,
});

describe("pasted recipe corpus", () => {
  it("has at least 20 fixtures", () => {
    expect(names.length).toBeGreaterThanOrEqual(20);
  });

  for (const name of names) {
    const { text, expected } = load(name);
    if (expected.needsModel) {
      it(`${name}: is left for the model`, () => {
        expect(readRecipeText(text)?.clarity).not.toBe("clear");
      });
      continue;
    }
    it(`${name}: reads clearly`, () => {
      const reading = readRecipeText(text);
      expect(reading?.clarity).toBe("clear");
      const recipe = reading!.recipe;
      expect(recipe.title).toBe(expected.title);
      expect(recipe.ingredients.map((i) => i.line)).toEqual(expected.ingredients);
      expect(recipe.steps.map((s) => s.text)).toEqual(expected.steps);
      if (expected.sections) {
        const sections = Object.fromEntries(
          recipe.ingredients.filter((i) => i.section !== null).map((i) => [i.line, i.section]),
        );
        expect(sections).toEqual(expected.sections);
      }
      if (expected.servings !== undefined) expect(recipe.servings).toBe(expected.servings);
    });
  }
});
