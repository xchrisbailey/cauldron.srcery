import { Effect, Layer } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { readableText, parseDocument } from "../src/imports/html.ts";
import { RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { isoMinutes, jsonLdRecipe, microdataRecipe } from "../src/imports/schemaOrg.ts";
import { fetchPage, fromHtml } from "../src/imports/web.ts";
import { RemoteFetch } from "../src/RemoteFetch.ts";

// Hostile and awkward pages: nothing here may hang the process, blow the
// stack, or credit a recipe to another site.

const BASE = "https://cook.example/recipes/x";
const ld = (value: unknown) =>
  `<script type="application/ld+json">${JSON.stringify(value)}</script>`;
const run = <A, E>(effect: Effect.Effect<A, E, RecipeExtractor | RemoteFetch>) =>
  Effect.runPromise(
    effect.pipe(Effect.provide(Layer.merge(RecipeExtractor.layerNone, RemoteFetch.layerTest({})))),
  );

describe("hostile pages", () => {
  it("reads a huge run of digits as no duration, quickly", () => {
    const start = performance.now();
    expect(isoMinutes("1".repeat(200_000))).toBeNull();
    expect(isoMinutes(`${"1".repeat(200_000)} minutes`)).toBeNull();
    expect(performance.now() - start).toBeLessThan(100);
    expect(isoMinutes("1 hr 20 mins")).toBe(80);
    expect(isoMinutes("PT1H20M")).toBe(80);
  });

  it("skips a JSON-LD script of newlines quickly", () => {
    const start = performance.now();
    const document = parseDocument(
      `<script type="application/ld+json">${"\n".repeat(200_000)}{}</script>`,
    );
    expect(jsonLdRecipe(document, BASE)).toBeNull();
    expect(performance.now() - start).toBeLessThan(500);
  });

  it("walks deeply nested markup without recursion", () => {
    const depth = 20_000;
    const html = `<body><article>${"<div>".repeat(depth)}1 onion${"</div>".repeat(depth)}</article></body>`;
    expect(readableText(parseDocument(html), 1000)).toBe("1 onion");
  });
});

describe("structured data", () => {
  it("doesn't split a microdata step on source line breaks", () => {
    const document = parseDocument(`<div itemscope itemtype="https://schema.org/Recipe">
      <h1 itemprop="name">Pancakes</h1>
      <span itemprop="recipeIngredient">1 cup flour</span>
      <div itemprop="recipeInstructions">
        <p>Whisk the eggs and milk until
          smooth and pale.</p>
        <p>Fry in butter.</p>
      </div>
    </div>`);
    expect(microdataRecipe(document, BASE)?.steps.map((s) => s.text)).toEqual([
      "Whisk the eggs and milk until smooth and pale.",
      "Fry in butter.",
    ]);
  });

  it("prefers full microdata over a stub JSON-LD Recipe", async () => {
    const html = `<head>${ld({ "@type": "Recipe", name: "Pancakes", image: "/p.jpg" })}</head>
      <body><div itemscope itemtype="https://schema.org/Recipe">
        <h1 itemprop="name">Pancakes</h1>
        <li itemprop="recipeIngredient">1 cup flour</li>
        <ol itemprop="recipeInstructions"><li>Mix.</li><li>Fry.</li></ol>
      </div></body>`;
    const read = await run(fromHtml(html, BASE));
    expect(read.extractor).toBe("microdata");
    expect(read.recipe.ingredients.map((i) => i.line)).toEqual(["1 cup flour"]);
  });

  it("only keeps a canonical link on the page's own site", async () => {
    const recipe = {
      "@type": "Recipe",
      name: "Dal",
      recipeIngredient: ["1 cup lentils"],
      recipeInstructions: ["Simmer."],
    };
    const elsewhere = await run(
      fromHtml(
        `<head>${ld(recipe)}<link rel="canonical" href="https://other.example/dal"></head>`,
        BASE,
      ),
    );
    expect(elsewhere.recipe.canonicalUrl).toBeNull();
    const own = await run(
      fromHtml(
        `<head>${ld(recipe)}<link rel="canonical" href="https://www.cook.example/dal"></head>`,
        BASE,
      ),
    );
    expect(own.recipe.canonicalUrl).toBe("https://www.cook.example/dal");
  });
});

describe("fetching a page", () => {
  const latin1 = new Uint8Array([
    ...new TextEncoder().encode("<p>Cr"),
    0xe8,
    ...new TextEncoder().encode("me br"),
  ]);

  it("decodes the charset the response declares", async () => {
    const page = await Effect.runPromise(
      fetchPage(BASE).pipe(
        Effect.provide(
          RemoteFetch.layerTest({
            [BASE]: { bytes: latin1, contentType: "text/html; charset=iso-8859-1" },
          }),
        ),
      ),
    );
    expect(page.html).toContain("Crème");
  });

  it("decodes the charset the page declares when the response doesn't", async () => {
    const bytes = new Uint8Array([
      ...new TextEncoder().encode('<meta charset="windows-1252">'),
      ...latin1,
    ]);
    const page = await Effect.runPromise(
      fetchPage(BASE).pipe(
        Effect.provide(RemoteFetch.layerTest({ [BASE]: { bytes, contentType: "text/html" } })),
      ),
    );
    expect(page.html).toContain("Crème");
  });
});
