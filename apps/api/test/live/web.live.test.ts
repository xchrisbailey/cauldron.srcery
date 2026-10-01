import { Effect, Layer } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { RecipeExtractor } from "../../src/imports/RecipeExtractor.ts";
import { fromWeb } from "../../src/imports/web.ts";
import { RemoteFetch } from "../../src/RemoteFetch.ts";

// A few real recipe sites, fetched for real. On demand only (`bun run
// test:live` in apps/api): sites change, and this is how we notice. No model
// is needed; each of these publishes JSON-LD.

const live = process.env.LIVE_IMPORTS === "1";

const SITES = [
  "https://www.bbcgoodfood.com/recipes/easy-pancakes",
  "https://www.recipetineats.com/chicken-chasseur/",
  "https://www.loveandlemons.com/hummus-recipe/",
  "https://www.bonappetit.com/recipe/bas-best-chocolate-chip-cookies",
];

describe.skipIf(!live)("live recipe sites", () => {
  it.each(SITES)("%s", { timeout: 30_000 }, async (url) => {
    const read = await Effect.runPromise(
      fromWeb(url).pipe(Effect.provide(Layer.merge(RemoteFetch.layer, RecipeExtractor.layerNone))),
    );
    expect(read.extractor).toBe("json-ld");
    expect(read.recipe.title).toBeTruthy();
    expect(read.recipe.ingredients.length).toBeGreaterThan(3);
    expect(read.recipe.steps.length).toBeGreaterThan(1);
  });
});
