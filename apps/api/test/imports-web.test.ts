import { copy, type ImportDraft } from "@cauldron/shared";
import { Effect, Layer } from "effect";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { Routes } from "../src/App.ts";
import { ImportWorker } from "../src/Imports.ts";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import { type ExtractInput, RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

// Website imports as jobs, with saved responses standing in for the network.

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

let api: AuthApi;
let ada: string;

beforeAll(async () => {
  const png = new Uint8Array(
    await sharp({
      create: { width: 60, height: 40, channels: 3, background: { r: 120, g: 60, b: 30 } },
    })
      .png()
      .toBuffer(),
  );
  api = makeAuthApi(
    {},
    Layer.merge(Routes, ImportWorker),
    {
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
    },
    fakeModel,
  );
  const before = (await api.outbox()).length;
  await api.post("/v1/auth/sign-up/email", {
    email: "ada@example.com",
    password: "correct-horse-1",
    name: "Ada",
  });
  const sentMail = await api.waitForOutbox(before + 1);
  ada = cookieOf(await api.send(api.linkIn(sentMail.at(-1)!)))!;
});
afterAll(() => api.dispose());

const call = async (method: string, path: string, body?: unknown) => {
  const res = await api.send(path, {
    method,
    headers: {
      cookie: ada,
      origin: WEB_ORIGIN,
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await res.text();
  // oxlint-disable-next-line typescript/no-explicit-any
  return { status: res.status, body: text ? JSON.parse(text) : (null as any) };
};

const distill = async (url: string) => {
  const started = await call("POST", "/v1/imports", { url });
  for (let i = 0; i < 500; i++) {
    const res = await call("GET", `/v1/imports/${started.body.id}`);
    if (!["queued", "running"].includes(res.body.status)) return res.body;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("import never settled");
};

describe("distilling a website", () => {
  it("reads JSON-LD without the model, keeps the canonical link and fetches the photo", async () => {
    const before = sent.length;
    const job = await distill("https://cook.example/tacos?utm_source=x");
    expect(job.status).toBe("done");
    const draft = job.draft as ImportDraft;
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
    expect(draft.photoKey).toMatch(/^[0-9a-f-]{36}$/);
    const photo = await api.send(`/v1/photos/${draft.photoKey}/thumb`, {
      headers: { cookie: ada },
    });
    expect(photo.status).toBe(200);
    expect(sent.length).toBe(before);
  });

  it("sends a page without recipe data to the model, as readable text", async () => {
    const job = await distill("https://blog.example/soup");
    expect(job.status).toBe("done");
    expect(sent.at(-1)?.kind).toBe("page");
    expect(sent.at(-1)?.text).toContain("1 onion");
    expect(sent.at(-1)?.text).not.toContain("Home Recipes Shop");
    // The og:image 404s: the draft just has no photo.
    expect(job.draft).toMatchObject({
      title: "Grandma's soup",
      photoKey: null,
      siteName: "blog.example",
    });
  });

  it("fails with plain copy when the link isn't a page it can read", async () => {
    expect((await distill("https://cook.example/menu.pdf")).failure).toEqual({
      code: "couldntRead",
      message: copy.imports.couldntRead.text,
    });
    expect((await distill("https://cook.example/missing")).failure.code).toBe("couldntRead");
  });

  it("warns about a duplicate once the canonical link is saved", async () => {
    const first = await distill("https://cook.example/tacos?utm_source=x");
    const saved = await call("POST", `/v1/imports/${first.id}/recipe`, {
      title: first.draft.title,
      description: null,
      servings: null,
      prepMinutes: null,
      cookMinutes: null,
      totalMinutes: null,
      sourcePlatform: "web",
      sourceUrl: first.draft.sourceUrl,
      sourceAuthor: null,
      notes: null,
      photoKey: null,
      tags: [],
      ingredients: [],
      steps: [],
    });
    expect(saved.status).toBe(200);
    const again = await distill("https://cook.example/tacos?utm_source=x");
    expect(again.duplicateOf).toEqual({ id: saved.body.id, title: "Smoky black bean tacos" });
  });
});
