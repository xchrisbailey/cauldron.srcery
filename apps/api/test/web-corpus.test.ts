import { readdirSync, readFileSync } from "node:fs";
import { Effect } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import { type ExtractInput, RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { fromHtml } from "../src/imports/web.ts";

// The website importer against saved pages (#14): hand-written pages shaped
// like what popular recipe sites publish, with no network. Each NN-name.html
// has an NN-name.json of what a cook should get back. Pages with structured
// recipe data are read without the model; the rest go to a fake model, and the
// readable text it is sent must hold the recipe and none of the page chrome.

interface Expected {
  readonly extractor: "json-ld" | "microdata" | "model";
  readonly title?: string;
  readonly ingredients?: ReadonlyArray<string>;
  readonly steps?: ReadonlyArray<string>;
  readonly sections?: Record<string, string>;
  readonly servings?: number;
  readonly prepMinutes?: number;
  readonly cookMinutes?: number;
  readonly totalMinutes?: number;
  readonly author?: string;
  readonly siteName?: string;
  readonly imageUrl?: string;
  readonly canonicalUrl?: string;
  readonly tags?: ReadonlyArray<string>;
  readonly textIncludes?: ReadonlyArray<string>;
  readonly textExcludes?: ReadonlyArray<string>;
}

const DIR = new URL("./fixtures/web/", import.meta.url);
const names = readdirSync(DIR)
  .filter((file) => file.endsWith(".html"))
  .map((file) => file.replace(/\.html$/, ""))
  .sort();

const read = (name: string, ext: "html" | "json") =>
  readFileSync(new URL(`${name}.${ext}`, DIR), "utf8");

/** The fake model: records what it is sent and answers with a small recipe. */
const sent: Array<ExtractInput> = [];
const fakeModel = RecipeExtractor.layerTest((input) => {
  sent.push(input);
  return Effect.succeed({
    ...emptyExtracted,
    ingredients: [{ line: "1 cup flour", section: null, unsure: false }],
    steps: [{ text: "Mix and bake.", section: null, unsure: false }],
  });
});

const run = (name: string, layer = fakeModel) =>
  Effect.runPromise(
    fromHtml(read(name, "html"), `https://example.com/recipes/${name.replace(/^\d+-/, "")}`).pipe(
      Effect.provide(layer),
    ),
  );

describe("website corpus", () => {
  it("has 30 pages", () => {
    expect(names).toHaveLength(30);
  });

  for (const name of names) {
    it(name, async () => {
      const want = JSON.parse(read(name, "json")) as Expected;
      sent.length = 0;
      const got = await run(name);
      const { recipe } = got;

      expect(got.extractor).toBe(want.extractor);
      if (want.extractor === "model") {
        expect(sent).toHaveLength(1);
        expect(sent[0]!.kind).toBe("page");
        expect(got.raw).toBe(sent[0]!.text);
      } else {
        expect(sent).toHaveLength(0);
        expect(got.raw).toBeNull();
        expect(got.usage).toBeNull();
      }

      if (want.title !== undefined) expect(recipe.title).toBe(want.title);
      if (want.ingredients) expect(recipe.ingredients.map((l) => l.line)).toEqual(want.ingredients);
      if (want.steps) expect(recipe.steps.map((s) => s.text)).toEqual(want.steps);
      if (want.sections) {
        for (const [text, section] of Object.entries(want.sections)) {
          expect(recipe.steps.find((s) => s.text === text)?.section, text).toBe(section);
        }
      }
      if (want.servings !== undefined) expect(recipe.servings).toBe(want.servings);
      if (want.prepMinutes !== undefined) expect(recipe.prepMinutes).toBe(want.prepMinutes);
      if (want.cookMinutes !== undefined) expect(recipe.cookMinutes).toBe(want.cookMinutes);
      if (want.totalMinutes !== undefined) expect(recipe.totalMinutes).toBe(want.totalMinutes);
      if (want.author !== undefined) expect(recipe.author).toBe(want.author);
      if (want.siteName !== undefined) expect(recipe.siteName).toBe(want.siteName);
      if (want.imageUrl !== undefined) expect(recipe.imageUrl).toBe(want.imageUrl);
      if (want.canonicalUrl !== undefined) expect(recipe.canonicalUrl).toBe(want.canonicalUrl);
      if (want.tags) expect(recipe.tags).toEqual(want.tags);

      for (const text of want.textIncludes ?? []) expect(got.raw, text).toContain(text);
      for (const text of want.textExcludes ?? []) expect(got.raw, text).not.toContain(text);
    });
  }

  it("keeps the ingredients of a page with no method when there is no model", async () => {
    const got = await run("20-jsonld-ingredients-only", RecipeExtractor.layerNone);
    expect(got.extractor).toBe("json-ld");
    expect(got.recipe.ingredients.map((l) => l.line)).toEqual([
      "4 tomatoes, diced",
      "1/2 onion, minced",
      "1 jalapeno, minced",
      "1/4 cup cilantro",
      "1 lime, juiced",
    ]);
    expect(got.recipe.steps).toEqual([]);
    expect(got.recipe.title).toBe("Pico de Gallo");
    expect(got.recipe.unsure).toContain("title");
  });

  it("fails with no recipe for a page without structured data and no model", async () => {
    const exit = await Effect.runPromiseExit(
      fromHtml(
        "<html><body><nav>Home</nav><p>Our story, and a photo of the shop.</p></body></html>",
        "https://example.com/recipes/x",
      ).pipe(Effect.provide(RecipeExtractor.layerNone)),
    );
    expect(exit._tag).toBe("Failure");
  });
});
