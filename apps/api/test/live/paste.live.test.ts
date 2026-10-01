import { readdirSync, readFileSync } from "node:fs";
import { Effect } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { fromText } from "../../src/imports/fromText.ts";
import { RecipeExtractor } from "../../src/imports/RecipeExtractor.ts";

// The pastes only the model can read, through the real model. On demand
// only, since it can cost money: `bun run test:live` in apps/api with
// GEMINI_API_KEY (or ANTHROPIC_API_KEY or OPENAI_API_KEY) set.

// Needs a model key; a run without one skips it.
const live =
  process.env.LIVE_IMPORTS === "1" &&
  Boolean(
    process.env.GEMINI_API_KEY || process.env.ANTHROPIC_API_KEY || process.env.OPENAI_API_KEY,
  );
const dir = new URL("../fixtures/paste/", import.meta.url);

const fixtures = readdirSync(dir)
  .filter((name) => name.endsWith(".json"))
  .map((name) => ({
    name: name.replace(/\.json$/, ""),
    expected: JSON.parse(readFileSync(new URL(name, dir), "utf8")) as {
      title: string;
      ingredients: Array<string>;
      steps: Array<string>;
      needsModel?: boolean;
    },
    text: readFileSync(new URL(name.replace(/\.json$/, ".txt"), dir), "utf8"),
  }))
  .filter((f) => f.expected.needsModel);

// Reads the key and model from the environment, like the API does.
const Model = RecipeExtractor.layer;

describe.skipIf(!live)("pastes read by the model", () => {
  it.each(fixtures)("$name", async ({ text, expected }) => {
    const read = await Effect.runPromise(fromText(text, "text").pipe(Effect.provide(Model)));
    expect(read.extractor).toBe("model");
    // Wording can differ; the count of lines and steps shouldn't.
    expect(read.recipe.ingredients).toHaveLength(expected.ingredients.length);
    expect(read.recipe.steps.length).toBeGreaterThan(0);
    expect(read.recipe.title).toBeTruthy();
  });
});
