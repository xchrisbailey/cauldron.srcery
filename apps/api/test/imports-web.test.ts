import { PhotoId } from "@cauldron/shared";
import { layer } from "@effect/vitest";
import { Effect } from "effect";
import sharp from "sharp";
import { expect } from "vite-plus/test";
import { distill } from "../src/imports/distill.ts";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import { type ExtractInput, RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { Photos } from "../src/Photos.ts";
import { DistillServices, makeOwner } from "./helpers.ts";

// Distilling a website, with saved responses standing in for the network.

const html = (body: string, head = "") =>
  new TextEncoder().encode(`<!doctype html><html><head>${head}</head><body>${body}</body></html>`);
const page = (bytes: Uint8Array, contentType = "text/html; charset=utf-8") => ({
  bytes,
  contentType,
});

const LD = {
  "@context": "https://schema.org",
  "@type": "Recipe",
  name: "Smoky black bean tacos",
  author: { "@type": "Person", name: "Ada Cook" },
  image: ["/img/tacos.png"],
  recipeYield: "4 servings",
  prepTime: "PT15M",
  cookTime: "PT20M",
  recipeCuisine: "Mexican",
  recipeIngredient: ["2 cans black beans, drained", "1 tsp smoked paprika", "8 corn tortillas"],
  recipeInstructions: [
    { "@type": "HowToStep", text: "Warm the beans with the paprika." },
    { "@type": "HowToStep", text: "Fill the tortillas." },
  ],
};

const sent: Array<ExtractInput> = [];
const fakeModel = RecipeExtractor.layerTest((input) => {
  sent.push(input);
  return Effect.succeed({
    ...emptyExtracted,
    title: "Grandma's soup",
    ingredients: [{ line: "1 onion", section: null, unsure: false }],
    steps: [{ text: "Simmer it.", section: null, unsure: false }],
  });
});

const png = new Uint8Array(
  await sharp({
    create: { width: 60, height: 40, channels: 3, background: { r: 120, g: 60, b: 30 } },
  })
    .png()
    .toBuffer(),
);

const responses = {
  "https://cook.example/tacos?utm_source=x": page(
    html(
      "<article><h1>Tacos</h1></article>",
      `<script type="application/ld+json">${JSON.stringify(LD)}</script>
       <link rel="canonical" href="https://cook.example/tacos/">
       <meta property="og:site_name" content="Cook Example">`,
    ),
  ),
  "https://cook.example/img/tacos.png": page(png, "image/png"),
  "https://blog.example/soup": page(
    html(
      `<nav>Home Recipes Shop</nav><article><h1>Grandma's soup</h1><p>My grandma made this.</p>
       <ul><li>1 onion</li></ul><p>Simmer it.</p></article><footer>© Blog</footer>`,
      `<meta property="og:image" content="https://blog.example/missing.jpg">`,
    ),
  ),
  "https://cook.example/menu.pdf": page(new Uint8Array([37, 80, 68, 70]), "application/pdf"),
};

layer(DistillServices(responses, fakeModel))("distilling a website", (it) => {
  it.effect("reads JSON-LD without the model, keeps the canonical link and stores the photo", () =>
    Effect.gen(function* () {
      const owner = yield* makeOwner();
      const before = sent.length;
      const { draft, extractor, usage } = yield* distill(
        { url: "https://cook.example/tacos?utm_source=x" },
        owner,
      );
      expect(draft).toMatchObject({
        title: "Smoky black bean tacos",
        servings: 4,
        prepMinutes: 15,
        cookMinutes: 20,
        sourcePlatform: "web",
        sourceUrl: "https://cook.example/tacos",
        sourceAuthor: "Ada Cook",
        siteName: "Cook Example",
        tags: ["Mexican"],
      });
      expect(draft.ingredients.map((i) => i.line)).toEqual(LD.recipeIngredient);
      expect(draft.steps.map((s) => s.text)).toEqual([
        "Warm the beans with the paprika.",
        "Fill the tortillas.",
      ]);
      expect({ extractor, usage }).toEqual({ extractor: "json-ld", usage: null });
      expect(draft.photoKey).toMatch(/^[0-9a-f-]{36}$/);
      const photos = yield* Photos;
      const thumb = yield* photos.read(owner, PhotoId.make(draft.photoKey!), "thumb");
      expect(thumb.byteLength).toBeGreaterThan(0);
      expect(sent.length).toBe(before);
    }),
  );

  it.effect("sends a page without recipe data to the model, as readable text", () =>
    Effect.gen(function* () {
      const owner = yield* makeOwner();
      const { draft, extractor, raw } = yield* distill({ url: "https://blog.example/soup" }, owner);
      expect(sent.at(-1)?.kind).toBe("page");
      expect(sent.at(-1)?.text).toContain("1 onion");
      expect(sent.at(-1)?.text).not.toContain("Home Recipes Shop");
      expect(extractor).toBe("model");
      // The page's text is kept on the job.
      expect(raw).toContain("1 onion");
      // The og:image 404s: the draft just has no photo.
      expect(draft).toMatchObject({
        title: "Grandma's soup",
        photoKey: null,
        siteName: "blog.example",
      });
    }),
  );

  it.effect("fails with a plain reason when the link isn't a page it can read", () =>
    Effect.gen(function* () {
      const owner = yield* makeOwner();
      const pdf = yield* Effect.flip(distill({ url: "https://cook.example/menu.pdf" }, owner));
      expect(pdf.code).toBe("couldntRead");
      const missing = yield* Effect.flip(distill({ url: "https://cook.example/missing" }, owner));
      expect(missing.code).toBe("couldntRead");
    }),
  );
});
