import { copy, type ImportDraft } from "@cauldron/shared";
import { schema } from "@cauldron/db";
import { eq } from "drizzle-orm";
import { Effect, Layer } from "effect";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { Routes } from "../src/App.ts";
import { Db } from "../src/Db.ts";
import { ImportWorker } from "../src/Imports.ts";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import { type ExtractInput, RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { canonicalPost, fromOpenGraph } from "../src/imports/social.ts";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

// Instagram and TikTok imports as jobs, with saved oEmbed and page responses
// standing in for the platforms.

const json = (value: unknown) => ({
  bytes: new TextEncoder().encode(JSON.stringify(value)),
  contentType: "application/json",
});
const html = (head: string, url?: string) => ({
  bytes: new TextEncoder().encode(`<!doctype html><html><head>${head}</head><body></body></html>`),
  contentType: "text/html",
  ...(url ? { url } : {}),
});

const CAPTION = `Crispy chilli oil noodles 🌶️ my go-to when I'm tired

Ingredients:
- 200g wheat noodles
- 2 tbsp chilli oil
- 1 tbsp soy sauce
- 1 spring onion, sliced

Method:
1. Cook the noodles and drain.
2. Toss with the chilli oil and soy.
3. Top with spring onion.

#noodles #easyrecipes #dinnerideas`;

const TIKTOK = "https://www.tiktok.com/@noodlecook/video/7301234567890123456";
const oembed = (url: string) => `https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`;

const sent: Array<ExtractInput> = [];
const fakeModel = RecipeExtractor.layerTest((input) => {
  sent.push(input);
  if (input.text.includes("full recipe in the video")) return Effect.succeed("inVideo" as const);
  if (input.text.includes("golden hour")) return Effect.succeed("missing" as const);
  return Effect.succeed({
    ...emptyExtracted,
    title: "Garlic butter rice",
    ingredients: [{ line: "1 cup rice", section: null, unsure: false }],
    steps: [{ text: "Cook the rice in butter.", section: null, unsure: false }],
  });
});

let api: AuthApi;
let ada: string;

beforeAll(async () => {
  api = makeAuthApi(
    {},
    Layer.merge(Routes, ImportWorker),
    {
      [oembed(TIKTOK)]: json({
        title: CAPTION,
        author_name: "Noodle Cook",
        author_unique_id: "noodlecook",
        thumbnail_url: "https://p16.tiktokcdn.example/cover.jpg",
      }),
      // A share link that redirects to the post.
      "https://vm.tiktok.com/ZMabc123/": html("", `${TIKTOK}?_r=1&u_code=xyz`),
      [oembed("https://www.tiktok.com/@ricecook/video/7300000000000000001")]: json({
        title: "garlic butter rice, so good, rice + butter + garlic then cook it all",
        author_unique_id: "ricecook",
      }),
      [oembed("https://www.tiktok.com/@spoken/video/7300000000000000002")]: json({
        title: "full recipe in the video 👀 #fyp",
        author_unique_id: "spoken",
      }),
      // No oEmbed caption: the page's Open Graph tags have it.
      "https://www.tiktok.com/@ogonly/video/7300000000000000003": html(
        `<meta property="og:description" content="${CAPTION.replace(/\n/g, "&#10;")}"><meta property="og:image" content="https://p16.tiktokcdn.example/og.jpg">`,
      ),
      "https://www.instagram.com/reel/Cxyz123/": html(
        `<meta property="og:description" content="1,204 likes, 33 comments - sunsetcook on May 2, 2026: &quot;golden hour on the terrace 🌅&quot;.">`,
      ),
    },
    fakeModel,
  );
  const before = (await api.outbox()).length;
  await api.post("/v1/auth/sign-up/email", {
    email: "ada@example.com",
    password: "correct-horse-1",
    name: "Ada",
  });
  ada = cookieOf(await api.send(api.linkIn((await api.waitForOutbox(before + 1)).at(-1)!)))!;
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

describe("post links", () => {
  it("finds the post behind each link shape", () => {
    expect(canonicalPost("instagram", "https://instagram.com/p/AbC_12-3/?igsh=xyz")).toBe(
      "https://www.instagram.com/p/AbC_12-3/",
    );
    expect(canonicalPost("instagram", "https://www.instagram.com/reels/AbC123/")).toBe(
      "https://www.instagram.com/reel/AbC123/",
    );
    expect(canonicalPost("instagram", "https://www.instagram.com/sunsetcook/reel/AbC123/")).toBe(
      "https://www.instagram.com/reel/AbC123/",
    );
    expect(canonicalPost("tiktok", `${TIKTOK}?is_from_webapp=1&sender_device=pc`)).toBe(TIKTOK);
    expect(canonicalPost("tiktok", "https://vm.tiktok.com/ZMabc123/")).toBeNull();
    expect(canonicalPost("instagram", "https://www.instagram.com/sunsetcook/")).toBeNull();
  });

  it("reads Instagram's Open Graph caption and handle", () => {
    expect(
      fromOpenGraph(
        `<meta property="og:description" content="12K likes, 80 comments - ada.cooks on March 1, 2026: &quot;Lemon pasta. Ingredients: pasta, lemon&quot;.">`,
      ),
    ).toEqual({
      caption: "Lemon pasta. Ingredients: pasta, lemon",
      author: "@ada.cooks",
      imageUrl: null,
    });
  });
});

describe("distilling a social post", () => {
  it("reads a laid-out caption from oEmbed without the model, crediting the creator", async () => {
    const before = sent.length;
    const job = await distill(`${TIKTOK}?is_from_webapp=1`);
    expect(job.status).toBe("done");
    expect(job.source).toBe("tiktok");
    const draft = job.draft as ImportDraft;
    expect(draft).toMatchObject({
      title: "Crispy chilli oil noodles 🌶️ my go-to when I'm tired",
      sourcePlatform: "tiktok",
      sourceUrl: TIKTOK,
      sourceAuthor: "@noodlecook",
      siteName: "TikTok",
    });
    expect(draft.ingredients.map((i) => i.line)).toEqual([
      "200g wheat noodles",
      "2 tbsp chilli oil",
      "1 tbsp soy sauce",
      "1 spring onion, sliced",
    ]);
    expect(draft.steps).toHaveLength(3);
    expect(draft.tags).toEqual([]);
    expect(sent.length).toBe(before);
  });

  it("follows a share link to the post", async () => {
    const job = await distill("https://vm.tiktok.com/ZMabc123/");
    expect(job.status).toBe("done");
    expect(job.draft.sourceUrl).toBe(TIKTOK);
  });

  it("sends a messy caption to the model, tuned for captions", async () => {
    const job = await distill("https://www.tiktok.com/@ricecook/video/7300000000000000001");
    expect(job.status).toBe("done");
    expect(sent.at(-1)?.kind).toBe("caption");
    expect(job.draft).toMatchObject({ title: "Garlic butter rice", sourceAuthor: "@ricecook" });
  });

  it("falls back to the page's Open Graph caption", async () => {
    const job = await distill("https://www.tiktok.com/@ogonly/video/7300000000000000003");
    expect(job.status).toBe("done");
    expect(job.draft.ingredients).toHaveLength(4);
  });

  it("fails with the paste suggestion when the recipe is only in the video, and keeps the caption", async () => {
    const spoken = await distill("https://www.tiktok.com/@spoken/video/7300000000000000002");
    expect(spoken.failure).toEqual({ code: "spokenOnly", message: copy.imports.spokenOnly.text });
    const insta = await distill("https://www.instagram.com/reel/Cxyz123/?igsh=abc");
    expect(insta.failure.code).toBe("spokenOnly");
    const row = await api.run(
      Effect.gen(function* () {
        const db = yield* Db;
        const [found] = yield* db.use((d) =>
          d.select().from(schema.importJob).where(eq(schema.importJob.id, spoken.id)),
        );
        return found!;
      }),
    );
    // Kept for #17, which will transcribe these.
    expect(row).toMatchObject({
      errorCode: "spokenOnly",
      rawContent: "full recipe in the video 👀 #fyp",
    });
  });

  it("can't read a post it can't reach", async () => {
    const job = await distill("https://www.tiktok.com/@gone/video/7300000000000000009");
    expect(job.failure.code).toBe("couldntRead");
  });
});
