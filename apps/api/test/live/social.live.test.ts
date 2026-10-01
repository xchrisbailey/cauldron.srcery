import { Effect, Redacted } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { capturePost } from "../../src/imports/social.ts";
import { RemoteFetch } from "../../src/RemoteFetch.ts";

// Real posts, read the way Distill reads them. On demand and on a schedule
// (.github/workflows/live-imports.yml): both platforms change their pages
// and endpoints, and a failure here is how we hear about it.

const live = process.env.LIVE_IMPORTS === "1";
const instagramToken = process.env.INSTAGRAM_OEMBED_TOKEN;

const capture = (source: "instagram" | "tiktok", url: string) =>
  Effect.runPromise(
    capturePost(source, url, {
      instagramToken: instagramToken ? Redacted.make(instagramToken) : undefined,
    }).pipe(Effect.provide(RemoteFetch.layer)),
  );

describe.skipIf(!live)("live social posts", () => {
  // TikTok's own oEmbed documentation example.
  it("reads a TikTok caption through oEmbed", { timeout: 30_000 }, async () => {
    const { post, capture: read } = await capture(
      "tiktok",
      "https://www.tiktok.com/@scout2015/video/6718335390845095173?is_from_webapp=1",
    );
    expect(post).toBe("https://www.tiktok.com/@scout2015/video/6718335390845095173");
    expect(read.caption).toBeTruthy();
    expect(read.author).toBe("@scout2015");
  });

  // Instagram's oEmbed needs a Meta app token; without one there's no check.
  it.skipIf(!instagramToken)("reads an Instagram caption", { timeout: 30_000 }, async () => {
    const { capture: read } = await capture(
      "instagram",
      process.env.INSTAGRAM_LIVE_POST ?? "https://www.instagram.com/p/C8QzE3fyN3J/",
    );
    expect(read.caption).toBeTruthy();
  });
});
