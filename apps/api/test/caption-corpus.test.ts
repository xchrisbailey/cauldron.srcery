import { readdirSync, readFileSync } from "node:fs";
import { Effect } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { fromText } from "../src/imports/fromText.ts";
import { RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { ImportFailed } from "../src/imports/result.ts";
import { readRecipeText } from "../src/imports/textRecipe.ts";

// Instagram and TikTok captions (#16): hand-written in the styles food posts
// use, with no network. Each NN-name.txt has an NN-name.json of what a cook
// should get back. Captions laid out with headings read without the model;
// captions that aren't go to it; captions with no recipe fail as noRecipe
// (the social importer reports that as spokenOnly).

interface Expected {
  readonly title?: string;
  readonly ingredients?: ReadonlyArray<string>;
  readonly steps?: ReadonlyArray<string>;
  readonly sections?: Record<string, string>;
  readonly needsModel?: true;
  readonly noRecipe?: true;
}

const DIR = new URL("./fixtures/captions/", import.meta.url);
const names = readdirSync(DIR)
  .filter((file) => file.endsWith(".txt"))
  .map((file) => file.replace(/\.txt$/, ""))
  .sort();

const read = (name: string, ext: "txt" | "json") =>
  readFileSync(new URL(`${name}.${ext}`, DIR), "utf8");

describe("caption corpus", () => {
  it("has 20 captions", () => {
    expect(names).toHaveLength(20);
  });

  for (const name of names) {
    it(name, async () => {
      const want = JSON.parse(read(name, "json")) as Expected;
      const caption = read(name, "txt");
      const reading = readRecipeText(caption);

      if (want.noRecipe) {
        expect(reading?.clarity).not.toBe("clear");
        const error = await Effect.runPromise(
          fromText(caption, "caption").pipe(Effect.provide(RecipeExtractor.layerNone), Effect.flip),
        );
        expect(error).toBeInstanceOf(ImportFailed);
        expect((error as ImportFailed).code).toBe("noRecipe");
        return;
      }
      if (want.needsModel) {
        expect(reading?.clarity).not.toBe("clear");
        return;
      }

      expect(reading?.clarity).toBe("clear");
      const { recipe } = reading!;
      if (want.title !== undefined) expect(recipe.title).toBe(want.title);
      expect(recipe.ingredients.map((l) => l.line)).toEqual(want.ingredients);
      expect(recipe.steps.map((s) => s.text)).toEqual(want.steps);
      for (const [line, section] of Object.entries(want.sections ?? {})) {
        expect(recipe.ingredients.find((l) => l.line === line)?.section, line).toBe(section);
      }
    });
  }
});
