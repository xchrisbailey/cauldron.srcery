import { type ImportDraft, type ImportSource, RECIPE_LIMITS, type UserId } from "@cauldron/shared";
import { Duration, Effect } from "effect";
import { AppConfig } from "../AppConfig.ts";
import { Photos } from "../Photos.ts";
import { toDraft } from "./draft.ts";
import type { ExtractedRecipe, Usage } from "./Extracted.ts";
import { fromText } from "./fromText.ts";
import { RecipeExtractor } from "./RecipeExtractor.ts";
import { ImportFailed, type Imported } from "./result.ts";
import { fromSocial, socialHost } from "./social.ts";
import { fromWeb } from "./web.ts";

// From a request to a draft: which kind of source it is, the importer for
// that kind, the cover photo and the macro estimate. Nothing here knows
// about jobs; the worker in Imports.ts runs this and records the result.
// Each importer tries its extractors in order, cheapest first, and fails
// with a typed reason the job turns into plain copy.

/** A distill gets this long; past it, it fails as timed out. */
export const DISTILL_TIMEOUT = Duration.minutes(2);
/** The cover photo gets this long; past it the draft goes without one. */
const PHOTO_TIMEOUT = Duration.seconds(20);
/** An estimate is a nicety: the draft goes out without one rather than waiting long. */
const MACRO_TIMEOUT = Duration.seconds(30);

/** A link to read, or text that was pasted. */
export type DistillRequest = { readonly url: string } | { readonly text: string };

export interface Distilled {
  readonly draft: ImportDraft;
  /** Which extractor read it: "json-ld", "microdata", "text" or "model". */
  readonly extractor: string;
  /** What was read (page text, caption), for the job row. */
  readonly raw: string | null;
  /** The model call it made, if any, for the cost log. */
  readonly usage: Usage | null;
}

/** What kind of source a link is, from its host. */
export const classify = (url: string): Exclude<ImportSource, "text"> => {
  try {
    return socialHost(new URL(url).hostname) ?? "web";
  } catch {
    return "web";
  }
};

const TRACKING = /^(?:utm_.*|fbclid|gclid|igshid|igsh|mc_cid|mc_eid|ref|ref_src|si|s)$/i;

/**
 * A link without the parts that don't change the page (fragment, tracking
 * parameters, a trailing slash, the host's case), so the same recipe is
 * recognised however it was shared.
 */
export const normalizeUrl = (raw: string): string => {
  try {
    const url = new URL(raw);
    url.hash = "";
    // Copied first: deleting while iterating skips keys.
    for (const key of Array.from(url.searchParams.keys())) {
      if (TRACKING.test(key)) url.searchParams.delete(key);
    }
    if (url.pathname.length > 1) url.pathname = url.pathname.replace(/\/+$/, "");
    return url.toString();
  } catch {
    return raw;
  }
};

/** Reads the recipe with the importer for the request's kind of source. */
const read = Effect.fn("Imports.read")(function* (request: DistillRequest) {
  if ("text" in request) {
    const read = yield* fromText(request.text, "text");
    return { ...read, raw: null, sourceUrl: null } satisfies Imported;
  }
  const source = classify(request.url);
  if (source === "web") return yield* fromWeb(request.url);
  const { instagramOEmbedToken } = yield* AppConfig;
  return yield* fromSocial(source, request.url, { instagramToken: instagramOEmbedToken });
});

/**
 * The hero image becomes the cover photo. One that won't fetch or decode in
 * time leaves the draft without a photo rather than failing it. A photo no
 * recipe ends up using is removed by the photo cleanup.
 */
const coverPhoto = Effect.fn("Imports.coverPhoto")(function* (
  ownerId: UserId,
  imageUrl: string | null,
) {
  if (imageUrl === null) return null;
  const photos = yield* Photos;
  return yield* photos.fromUrl(ownerId, imageUrl).pipe(
    Effect.map((photo): string | null => photo.id),
    Effect.timeoutOrElse({ duration: PHOTO_TIMEOUT, orElse: () => Effect.succeed(null) }),
    Effect.catchCause((cause) =>
      Effect.logInfo("Import photo skipped", cause).pipe(Effect.as(null)),
    ),
  );
});

/**
 * A recipe whose source gave no nutrition gets the model's estimate from its
 * ingredients, flagged for the cook to check. No model, or a failed or slow
 * estimate, leaves the macros blank rather than failing the import.
 */
const withMacros = Effect.fn("Imports.withMacros")(function* (recipe: ExtractedRecipe) {
  const model = yield* RecipeExtractor;
  const lines = recipe.ingredients
    .map((l) => l.line.trim().slice(0, RECIPE_LIMITS.line))
    .filter((l) => l !== "")
    .slice(0, RECIPE_LIMITS.ingredients);
  if (recipe.macros !== undefined || !model.available || lines.length === 0) return recipe;
  const macros = yield* model
    .estimateMacros({
      title: recipe.title?.slice(0, RECIPE_LIMITS.title) ?? null,
      servings:
        recipe.servings !== null &&
        recipe.servings >= 1 &&
        recipe.servings <= RECIPE_LIMITS.servings
          ? Math.round(recipe.servings)
          : null,
      ingredients: lines,
    })
    .pipe(
      Effect.timeoutOrElse({ duration: MACRO_TIMEOUT, orElse: () => Effect.succeed(null) }),
      Effect.catchCause((cause) =>
        Effect.logInfo("Import macro estimate skipped", cause).pipe(Effect.as(null)),
      ),
    );
  if (macros === null) return recipe;
  return { ...recipe, macros, unsure: [...recipe.unsure, "macros" as const] };
});

/**
 * Turns a link or pasted text into a draft for `ownerId` to review, with its
 * cover photo stored. Fails with a plain reason the job shows the cook.
 */
export const distill = Effect.fn("Imports.distill")(
  function* (request: DistillRequest, ownerId: UserId) {
    const imported = yield* read(request);
    const photoKey = yield* coverPhoto(ownerId, imported.recipe.imageUrl);
    const recipe = yield* withMacros(imported.recipe);
    const link = imported.sourceUrl ?? ("url" in request ? request.url : null);
    const draft = toDraft(recipe, {
      source: "text" in request ? "text" : classify(request.url),
      sourceUrl: link === null ? null : normalizeUrl(link),
      photoKey,
    });
    return {
      draft,
      extractor: imported.extractor,
      raw: imported.raw,
      usage: imported.usage,
    } satisfies Distilled;
  },
  Effect.timeoutOrElse({
    duration: DISTILL_TIMEOUT,
    orElse: () => Effect.fail(new ImportFailed({ code: "timeout" })),
  }),
);
