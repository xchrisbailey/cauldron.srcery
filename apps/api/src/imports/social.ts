import type { ImportSource } from "@cauldron/shared";
import { Effect, Option, Redacted, Schema } from "effect";
import { RemoteFetch } from "../RemoteFetch.ts";
import { fromText } from "./fromText.ts";
import { RecipeExtractor } from "./RecipeExtractor.ts";
import { parseDocument } from "./html.ts";
import { failed, ImportFailed, type Imported } from "./result.ts";
import { fetchFailure, fetchPage } from "./web.ts";

// Distill from Instagram and TikTok posts (#16). v1 reads the caption only:
// the platform's oEmbed endpoint first, then the post page's Open Graph tags.
// Both platforms change their pages and limit scraping, so everything
// platform-specific is in this one file, behind `fromSocial`, with fixture
// tests and a scheduled live check (test/live) that fails loudly when a
// platform changes.

export type SocialSource = Extract<ImportSource, "instagram" | "tiktok">;

// The optional first segment is a username ("instagram.com/ada/reel/…"), never
// a reserved path: "/share/reel/…" is a share link with its own code, which
// has to be followed to find the post.
const INSTAGRAM_POST =
  /^https?:\/\/(?:www\.|m\.)?instagram\.com\/(?:(?!share\/|stories\/|explore\/|accounts\/)[\w.]+\/)?(p|reels?|tv)\/([\w-]+)/i;
const TIKTOK_POST = /^https?:\/\/(?:www\.|m\.)?tiktok\.com\/@([\w.-]+)\/(video|photo)\/(\d+)/i;

/** The post's own link, without tracking or share parameters, or null for a share link. */
export const canonicalPost = (source: SocialSource, url: string): string | null => {
  if (source === "instagram") {
    const match = INSTAGRAM_POST.exec(url);
    if (!match) return null;
    const kind =
      match[1]!.toLowerCase() === "p" ? "p" : match[1]!.toLowerCase() === "tv" ? "tv" : "reel";
    return `https://www.instagram.com/${kind}/${match[2]}/`;
  }
  const match = TIKTOK_POST.exec(url);
  return match
    ? `https://www.tiktok.com/@${match[1]}/${match[2]!.toLowerCase()}/${match[3]}`
    : null;
};

const OEmbed = Schema.Struct({
  title: Schema.optional(Schema.String),
  author_name: Schema.optional(Schema.String),
  author_unique_id: Schema.optional(Schema.String),
  author_url: Schema.optional(Schema.String),
  thumbnail_url: Schema.optional(Schema.String),
  html: Schema.optional(Schema.String),
});
const decodeOEmbed = Schema.decodeUnknownOption(Schema.fromJsonString(OEmbed));

export interface Capture {
  readonly caption: string | null;
  /** "@handle" when the platform gives one, otherwise the display name. */
  readonly author: string | null;
  readonly imageUrl: string | null;
}

const handleFrom = (url: string | undefined) => {
  const match = url ? /\/@?([\w.-]+)\/?$/.exec(url) : null;
  return match ? `@${match[1]!.replace(/^@/, "")}` : null;
};

/** The caption out of an embed's blockquote, when the endpoint only sends HTML. */
const captionFromEmbed = (html: string): string | null => {
  const document = parseDocument(html);
  const paragraph = document.querySelector("blockquote p") ?? document.querySelector("p");
  const text = paragraph?.textContent?.trim();
  return text ? text : null;
};

/** What an oEmbed response says about a post. */
export const fromOEmbed = (json: string): Capture | null => {
  const decoded = Option.getOrNull(decodeOEmbed(json));
  if (!decoded) return null;
  const caption = decoded.title?.trim() || (decoded.html ? captionFromEmbed(decoded.html) : null);
  return {
    caption: caption || null,
    author: decoded.author_unique_id
      ? `@${decoded.author_unique_id}`
      : (handleFrom(decoded.author_url) ?? decoded.author_name ?? null),
    imageUrl: decoded.thumbnail_url ?? null,
  };
};

const meta = (document: ReturnType<typeof parseDocument>, key: string) => {
  const el =
    document.querySelector(`meta[property="${key}"]`) ??
    document.querySelector(`meta[name="${key}"]`);
  // Attributes come back with entities decoded; line breaks are kept, since
  // a caption's layout is how the text reader finds its sections.
  const content = el?.getAttribute("content")?.trim();
  return content ? content : null;
};

// Instagram's description reads `123 likes, 4 comments - ada on March 1, 2026: "caption".`
// and its title `Ada on Instagram: "caption"`.
const CAPTION_MAX = 8000;
const QUOTED = /:\s*["“]([\s\S]+)["”]\s*\.?\s*$/;
const INSTAGRAM_HANDLE = /\d[\d,.]*\s*[KM]?\s+(?:likes?|comments?)[^-]*-\s*([\w.]+)\s+on\s/i;

/** What a post page's Open Graph tags say about it. */
export const fromOpenGraph = (html: string, source: SocialSource): Capture | null => {
  const document = parseDocument(html);
  // Captions are a few thousand characters at most; the cap also bounds the regexes.
  const cap = (text: string | null) => text?.slice(0, CAPTION_MAX) ?? null;
  const description = cap(meta(document, "og:description") ?? meta(document, "description"));
  const title = cap(meta(document, "og:title"));
  const raw = description ?? title;
  if (!raw) return null;
  // Only Instagram wraps the caption in quotes after its counts; a TikTok
  // caption's own quotes are part of it.
  const instagram = source === "instagram";
  const quoted = instagram
    ? (QUOTED.exec(raw)?.[1] ?? (title ? QUOTED.exec(title)?.[1] : undefined))
    : undefined;
  const handle = instagram && description ? INSTAGRAM_HANDLE.exec(description)?.[1] : undefined;
  return {
    caption: (quoted ?? raw).trim() || null,
    author: handle ? `@${handle}` : null,
    imageUrl: meta(document, "og:image"),
  };
};

export interface SocialConfig {
  /** A Meta app token ("app-id|client-token") for Instagram's oEmbed. Without one, Open Graph only. */
  readonly instagramToken: Redacted.Redacted<string> | undefined;
}

/** Meta retires Graph API versions about two years after release; bump it then. */
const GRAPH_VERSION = "v21.0";

const oEmbedUrl = (source: SocialSource, post: string, config: SocialConfig) => {
  if (source === "tiktok") return `https://www.tiktok.com/oembed?url=${encodeURIComponent(post)}`;
  if (!config.instagramToken) return null;
  const token = encodeURIComponent(Redacted.value(config.instagramToken));
  return `https://graph.facebook.com/${GRAPH_VERSION}/instagram_oembed?url=${encodeURIComponent(post)}&access_token=${token}`;
};

/** Finds the post behind a link (share links redirect) and reads its caption. */
export const capturePost = Effect.fn("Social.capture")(function* (
  source: SocialSource,
  url: string,
  config: SocialConfig,
) {
  const remote = yield* RemoteFetch;
  let page: { html: string; url: string } | null = null;
  let post = canonicalPost(source, url);
  if (post === null) {
    // A share link ("vm.tiktok.com/…", "instagram.com/share/…"): follow it.
    page = yield* fetchPage(url);
    // A logged-out visit can land on "/accounts/login/?next=/reel/ID/".
    const landed = new URL(page.url);
    const next = landed.searchParams.get("next");
    post =
      canonicalPost(source, page.url) ??
      (next ? canonicalPost(source, new URL(next, landed).toString()) : null);
    if (post === null) return yield* failed("couldntRead");
  }
  const endpoint = oEmbedUrl(source, post, config);
  const embedded = endpoint
    ? yield* remote.get(endpoint, { maxBytes: 512 * 1024, accept: "application/json" }).pipe(
        Effect.map((res) => fromOEmbed(new TextDecoder().decode(res.bytes))),
        // A missing or private post fails here too; the page may still say more.
        Effect.catchTag("FetchError", (error) =>
          error.reason === "blocked"
            ? Effect.fail(fetchFailure(error))
            : // Never the URL: Instagram's carries the token.
              Effect.logWarning("oEmbed failed", {
                source,
                reason: error.reason,
                detail: error.detail,
              }).pipe(Effect.as(null)),
        ),
      )
    : null;
  if (embedded?.caption) return { post, capture: embedded };
  page ??= yield* fetchPage(post);
  const graph = fromOpenGraph(page.html, source);
  const capture: Capture = {
    caption: graph?.caption ?? null,
    author: embedded?.author ?? graph?.author ?? null,
    imageUrl: embedded?.imageUrl ?? graph?.imageUrl ?? null,
  };
  return { post, capture };
});

const SITE: Record<SocialSource, string> = { instagram: "Instagram", tiktok: "TikTok" };

export const fromSocial = Effect.fn("Social.fromSocial")(function* (
  source: SocialSource,
  url: string,
  config: SocialConfig,
) {
  const { post, capture } = yield* capturePost(source, url, config);
  // No caption at all: whatever the recipe is, it's in the video (#17).
  if (!capture.caption) return yield* failed("spokenOnly");
  const caption = capture.caption;
  // Only the model can tell a caption without a recipe from one it can't lay
  // out; without one, it's "no recipe found", not "spoken in the video".
  const { available } = yield* RecipeExtractor;
  const read = yield* fromText(caption, "caption").pipe(
    Effect.catchTag("ImportFailed", (failure) =>
      Effect.fail(
        new ImportFailed({
          code: failure.code === "noRecipe" && available ? "spokenOnly" : failure.code,
          raw: caption,
        }),
      ),
    ),
  );
  return {
    ...read,
    recipe: {
      ...read.recipe,
      author: capture.author ?? read.recipe.author,
      siteName: SITE[source],
      imageUrl: capture.imageUrl,
      canonicalUrl: post,
    },
    raw: capture.caption,
    sourceUrl: post,
  } satisfies Imported;
});
