import type { ImportDraft } from "@cauldron/shared";
import { layer } from "@effect/vitest";
import { Effect } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { distill } from "../src/imports/distill.ts";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import { type ExtractInput, RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { canonicalPost, fromOpenGraph } from "../src/imports/social.ts";
import { DistillServices, makeOwner } from "./helpers.ts";

// Distilling Instagram and TikTok posts, with saved oEmbed and page responses
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

const responses = {
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
  "https://www.instagram.com/share/reel/BAGshare1/": html(
    "",
    "https://www.instagram.com/accounts/login/?next=%2Freel%2FCxyz123%2F",
  ),
  "https://www.instagram.com/reel/Cxyz123/": html(
    `<meta property="og:description" content="1,204 likes, 33 comments - sunsetcook on May 2, 2026: &quot;golden hour on the terrace 🌅&quot;.">`,
  ),
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
    // Share links carry their own code: they're followed, not read as posts.
    expect(
      canonicalPost("instagram", "https://www.instagram.com/share/reel/BAGxyz123/"),
    ).toBeNull();
    expect(canonicalPost("instagram", "https://www.instagram.com/share/p/BAGxyz123/")).toBeNull();
    expect(canonicalPost("instagram", "https://www.instagram.com/sunsetcook/")).toBeNull();
  });

  it("reads Instagram's Open Graph caption and handle", () => {
    expect(
      fromOpenGraph(
        `<meta property="og:description" content="12K likes, 80 comments - ada.cooks on March 1, 2026: &quot;Lemon pasta. Ingredients: pasta, lemon&quot;.">`,
        "instagram",
      ),
    ).toEqual({
      caption: "Lemon pasta. Ingredients: pasta, lemon",
      author: "@ada.cooks",
      imageUrl: null,
    });
  });

  it("keeps a TikTok caption's own quotes", () => {
    expect(
      fromOpenGraph(
        `<meta property="og:description" content="Pasta night. Top tip: &quot;salt the water&quot;">`,
        "tiktok",
      )?.caption,
    ).toBe('Pasta night. Top tip: "salt the water"');
  });
});

layer(DistillServices(responses, fakeModel))("distilling a social post", (it) => {
  const read = (url: string) =>
    Effect.gen(function* () {
      return yield* distill({ url }, yield* makeOwner());
    });
  const failure = (url: string) =>
    Effect.gen(function* () {
      return yield* Effect.flip(distill({ url }, yield* makeOwner()));
    });

  it.effect("reads a laid-out caption from oEmbed without the model, crediting the creator", () =>
    Effect.gen(function* () {
      const before = sent.length;
      const { draft, extractor, raw } = yield* read(`${TIKTOK}?is_from_webapp=1`);
      expect(draft).toMatchObject({
        title: "Crispy chilli oil noodles 🌶️ my go-to when I'm tired",
        sourcePlatform: "tiktok",
        sourceUrl: TIKTOK,
        sourceAuthor: "@noodlecook",
        siteName: "TikTok",
      } satisfies Partial<ImportDraft>);
      expect(draft.ingredients.map((i) => i.line)).toEqual([
        "200g wheat noodles",
        "2 tbsp chilli oil",
        "1 tbsp soy sauce",
        "1 spring onion, sliced",
      ]);
      expect(draft.steps).toHaveLength(3);
      expect(draft.tags).toEqual([]);
      expect({ extractor, raw }).toEqual({ extractor: "text", raw: CAPTION });
      expect(sent.length).toBe(before);
    }),
  );

  it.effect("follows a share link to the post", () =>
    Effect.gen(function* () {
      const { draft } = yield* read("https://vm.tiktok.com/ZMabc123/");
      expect(draft.sourceUrl).toBe(TIKTOK);
    }),
  );

  it.effect("sends a messy caption to the model, tuned for captions", () =>
    Effect.gen(function* () {
      const { draft, usage } = yield* read(
        "https://www.tiktok.com/@ricecook/video/7300000000000000001",
      );
      expect(sent.at(-1)?.kind).toBe("caption");
      expect(draft).toMatchObject({ title: "Garlic butter rice", sourceAuthor: "@ricecook" });
      expect(usage?.model).toBe("fake");
    }),
  );

  it.effect("falls back to the page's Open Graph caption", () =>
    Effect.gen(function* () {
      const { draft } = yield* read("https://www.tiktok.com/@ogonly/video/7300000000000000003");
      expect(draft.ingredients).toHaveLength(4);
    }),
  );

  it.effect(
    "fails with the paste suggestion when the recipe is only in the video, and keeps the caption",
    () =>
      Effect.gen(function* () {
        const spoken = yield* failure("https://www.tiktok.com/@spoken/video/7300000000000000002");
        // Kept for #17, which will transcribe these.
        expect({ code: spoken.code, raw: spoken.raw }).toEqual({
          code: "spokenOnly",
          raw: "full recipe in the video 👀 #fyp",
        });
        const insta = yield* failure("https://www.instagram.com/reel/Cxyz123/?igsh=abc");
        expect(insta.code).toBe("spokenOnly");
      }),
  );

  it.effect("follows an Instagram share link, even to a login page", () =>
    Effect.gen(function* () {
      // The share code isn't the post's; the redirect says where the post is.
      const error = yield* failure("https://www.instagram.com/share/reel/BAGshare1/");
      expect(error.code).toBe("spokenOnly");
    }),
  );

  it.effect("can't read a post it can't reach", () =>
    Effect.gen(function* () {
      const error = yield* failure("https://www.tiktok.com/@gone/video/7300000000000000009");
      expect(error.code).toBe("couldntRead");
    }),
  );
});
