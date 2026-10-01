import { layer } from "@effect/vitest";
import { Effect, Fiber } from "effect";
import { TestClock } from "effect/testing";
import { describe, expect, it } from "vite-plus/test";
import { classify, DISTILL_TIMEOUT, distill, normalizeUrl } from "../src/imports/distill.ts";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import {
  ExtractError,
  type ExtractInput,
  RecipeExtractor,
} from "../src/imports/RecipeExtractor.ts";
import { readRecipeText } from "../src/imports/textRecipe.ts";
import { DistillServices, makeOwner } from "./helpers.ts";

// Distilling pasted text, and what every distill shares: telling sources
// apart, tidying links and the time limit.

const PASTED = `Weeknight dal

A quick red lentil dal.

Serves 4
Prep: 10 mins | Cook: 30 mins

Ingredients
- 1 cup red lentils, rinsed
- 1 onion, finely chopped
- 2 tsp ground cumin

Method
1. Fry the onion until soft.
2. Add the lentils, cumin and 3 cups water.
3. Simmer for 25 minutes.`;

// A paste with no headings, which the text reader can't lay out by itself.
const MESSY = "made this dal last night, lentils + onion + cumin, simmer it all, so good";

// The fake model: a recipe for MESSY, nothing for "no recipe here", a failure
// for "flaky", and a reading that never finishes for "hang".
const calls: Array<ExtractInput> = [];
const fakeModel = RecipeExtractor.layerTest((input) => {
  calls.push(input);
  if (input.text.includes("hang")) return Effect.never;
  if (input.text.includes("flaky")) return Effect.fail(new ExtractError({ reason: "failed" }));
  if (input.text.includes("no recipe here")) return Effect.succeed("missing" as const);
  return Effect.succeed({
    ...emptyExtracted,
    title: "Last night's dal",
    servings: 2,
    ingredients: [
      { line: "1 cup red lentils", section: null, unsure: false },
      { line: "some cumin", section: null, unsure: true },
    ],
    steps: [{ text: "Simmer it all.", section: null, unsure: false }],
    unsure: ["servings"],
  });
});

const read = (text: string) =>
  Effect.gen(function* () {
    return yield* distill({ text }, yield* makeOwner());
  });
const failure = (text: string) =>
  Effect.gen(function* () {
    return yield* Effect.flip(distill({ text }, yield* makeOwner()));
  });

layer(DistillServices({}, fakeModel))("distilling pasted text", (it) => {
  it.effect("reads a laid-out paste without the model", () =>
    Effect.gen(function* () {
      const before = calls.length;
      const { draft, extractor, raw, usage } = yield* read(PASTED);
      expect(draft).toMatchObject({
        title: "Weeknight dal",
        description: "A quick red lentil dal.",
        servings: 4,
        prepMinutes: 10,
        cookMinutes: 30,
        sourcePlatform: "text",
        sourceUrl: null,
        photoKey: null,
        unsure: [],
      });
      expect(draft.ingredients.map((i) => i.line)).toEqual([
        "1 cup red lentils, rinsed",
        "1 onion, finely chopped",
        "2 tsp ground cumin",
      ]);
      expect(draft.steps.map((s) => s.text)).toEqual([
        "Fry the onion until soft.",
        "Add the lentils, cumin and 3 cups water.",
        "Simmer for 25 minutes.",
      ]);
      expect({ extractor, raw, usage }).toEqual({ extractor: "text", raw: null, usage: null });
      expect(calls.length).toBe(before);
    }),
  );

  it.effect("sends messy text to the model and reports its cost", () =>
    Effect.gen(function* () {
      const { draft, extractor, usage } = yield* read(MESSY);
      expect(calls.at(-1)).toEqual({ text: MESSY, kind: "text" });
      expect(draft).toMatchObject({
        title: "Last night's dal",
        servings: 2,
        unsure: ["servings"],
        ingredients: [
          { line: "1 cup red lentils", unsure: false },
          { line: "some cumin", unsure: true },
        ],
      });
      expect(extractor).toBe("model");
      expect(usage).toEqual({ model: "fake", inputTokens: MESSY.length, outputTokens: 100 });
    }),
  );

  it.effect("fails as no recipe when there isn't one", () =>
    Effect.gen(function* () {
      const error = yield* failure("no recipe here, just chat");
      expect(error.code).toBe("noRecipe");
    }),
  );

  it.effect("falls back to the rough reading when the model fails", () =>
    Effect.gen(function* () {
      const { draft, extractor } = yield* read(
        "flaky dal\n1 cup red lentils\n2 tsp cumin\nSimmer the lentils with the cumin until soft.",
      );
      expect(draft.ingredients.map((i) => i.line)).toEqual(["1 cup red lentils", "2 tsp cumin"]);
      expect(draft.unsure).toContain("title");
      expect(extractor).toBe("text");
    }),
  );

  it.effect("times out a distill that runs too long", () =>
    Effect.gen(function* () {
      const fiber = yield* Effect.forkChild(failure("hang on, this takes a while"));
      // Moves time on in steps, so the limit passes however late its timer starts.
      for (let i = 0; i < 10 && !fiber.pollUnsafe(); i++) {
        yield* TestClock.adjust(DISTILL_TIMEOUT);
      }
      expect((yield* Fiber.join(fiber)).code).toBe("timeout");
    }),
  );
});

describe("sources", () => {
  it("tells a link's kind from its host", () => {
    expect(classify("https://www.instagram.com/reel/abc123/")).toBe("instagram");
    expect(classify("https://instagr.am/p/abc123/")).toBe("instagram");
    expect(classify("https://vm.tiktok.com/ZM123/")).toBe("tiktok");
    expect(classify("https://example.com/dal")).toBe("web");
    expect(classify("https://notinstagram.com/dal")).toBe("web");
  });

  it("drops what doesn't change the page from a link", () => {
    expect(normalizeUrl("https://Example.com/recipes/dal/?utm_source=share&id=2#jump")).toBe(
      "https://example.com/recipes/dal?id=2",
    );
  });
});

describe("the text reader", () => {
  it("keeps method steps that start like a time line", () => {
    const reading = readRecipeText(`Onion soup

Prep: 10 mins

Ingredients
- 4 onions, sliced
- 1 litre stock

Method
- Cook the onions for 40 minutes until soft.
- Bake for 10 minutes.
- Cook pasta 10 minutes.`);
    expect(reading?.recipe.prepMinutes).toBe(10);
    expect(reading?.recipe.cookMinutes).toBeNull();
    expect(reading?.recipe.steps.map((s) => s.text)).toEqual([
      "Cook the onions for 40 minutes until soft.",
      "Bake for 10 minutes.",
      "Cook pasta 10 minutes.",
    ]);
  });
});
