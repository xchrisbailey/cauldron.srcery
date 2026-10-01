import { Effect, Schedule } from "effect";
import { type FetchError, RemoteFetch } from "../RemoteFetch.ts";
import { type ExtractedRecipe, hasRecipe } from "./Extracted.ts";
import { decodeHtml, type PageMeta, pageMeta, parseDocument, readableText } from "./html.ts";
import { fromText } from "./fromText.ts";
import { ImportFailed, type Imported } from "./result.ts";
import { MODEL_INPUT_MAX } from "./RecipeExtractor.ts";
import { jsonLdRecipe, microdataRecipe } from "./schemaOrg.ts";

// Distill from a website (#14). The page is fetched on the server through
// RemoteFetch (SSRF-guarded, size- and time-capped). Its schema.org Recipe
// data is read first, JSON-LD then microdata, with no model. Pages without it
// have their readable text sent to the model.

/** Recipe pages are rarely over 1 MB; some carry a lot of inline script. */
export const PAGE_MAX_BYTES = 5 * 1024 * 1024;

const HTML = /^(?:text\/html|application\/xhtml\+xml|text\/plain|application\/xml|text\/xml)\b/i;

// Not a name that doesn't resolve: that won't pass on a retry.
const transient = (error: FetchError) =>
  (error.reason === "unreachable" && error.detail !== "dns") ||
  error.reason === "timeout" ||
  (error.reason === "status" && /^(?:5\d\d|429)$/.test(error.detail ?? ""));

export const fetchFailure = (error: FetchError) =>
  new ImportFailed({
    code:
      error.reason === "blocked"
        ? "blocked"
        : error.reason === "tooLarge"
          ? "tooLarge"
          : error.reason === "timeout"
            ? "timeout"
            : "couldntRead",
  });

/** Fetches a page, retrying twice on errors that may pass. */
export const fetchPage = Effect.fn("Web.fetchPage")(function* (url: string) {
  const remote = yield* RemoteFetch;
  const page = yield* remote
    .get(url, {
      maxBytes: PAGE_MAX_BYTES,
      accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5",
    })
    .pipe(
      Effect.retry({
        schedule: Schedule.exponential("400 millis"),
        times: 2,
        while: transient,
      }),
      Effect.mapError(fetchFailure),
    );
  if (page.contentType !== null && !HTML.test(page.contentType)) {
    return yield* new ImportFailed({ code: "couldntRead" });
  }
  return { html: decodeHtml(page.bytes, page.contentType), url: page.url };
});

const site = (href: string) => {
  try {
    return new URL(href).hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
};

/**
 * A canonical link only counts when it's on the page's own site (or one of
 * its subdomains), so a page can't make its recipe credit somewhere else.
 */
const sameSite = (canonical: string | null, page: string): string | null => {
  const a = canonical ? site(canonical) : null;
  const b = site(page);
  if (!a || !b) return null;
  return a === b || a.endsWith(`.${b}`) || b.endsWith(`.${a}`) ? canonical : null;
};

/** Fills what the recipe data left out from the page's own metadata. */
const withMeta = (recipe: ExtractedRecipe, meta: PageMeta, url: string): ExtractedRecipe => ({
  ...recipe,
  title: recipe.title ?? meta.title,
  description: recipe.description ?? meta.description,
  author: recipe.author ?? meta.author,
  siteName: recipe.siteName ?? meta.siteName ?? new URL(url).hostname.replace(/^www\./, ""),
  imageUrl: recipe.imageUrl ?? meta.imageUrl,
  canonicalUrl: sameSite(meta.canonicalUrl, url) ?? sameSite(recipe.canonicalUrl, url),
});

/** Reads a recipe from a page's HTML. Exported for the fixture tests, which have no network. */
export const fromHtml = Effect.fn("Web.fromHtml")(function* (html: string, url: string) {
  const document = parseDocument(html);
  const meta = pageMeta(document, url);
  // A stub JSON-LD Recipe (a name and a photo) doesn't hide full microdata.
  const jsonLd = jsonLdRecipe(document, url);
  const microdata = jsonLd && hasRecipe(jsonLd) ? null : microdataRecipe(document, url);
  const useMicrodata = microdata !== null && (hasRecipe(microdata) || jsonLd === null);
  const structured = useMicrodata ? microdata : jsonLd;
  const extractor = useMicrodata ? "microdata" : "json-ld";
  if (structured && hasRecipe(structured)) {
    return { recipe: withMeta(structured, meta, url), extractor, usage: null, raw: null };
  }
  const text = readableText(document, MODEL_INPUT_MAX);
  const read = yield* fromText(text, "page").pipe(
    Effect.map((read) => ({
      ...read,
      // The model reads the method; titles and photos from the page's own data win.
      recipe: withMeta(
        structured
          ? {
              ...read.recipe,
              ...Object.fromEntries(
                Object.entries(structured).filter(
                  ([key, value]) =>
                    !["ingredients", "steps", "unsure"].includes(key) &&
                    value !== null &&
                    !(Array.isArray(value) && value.length === 0),
                ),
              ),
            }
          : read.recipe,
        meta,
        url,
      ),
    })),
    Effect.catchTag("ImportFailed", (failure) =>
      // Ingredients without a method are still worth reviewing.
      structured && structured.ingredients.length > 0 && failure.code !== "timeout"
        ? Effect.succeed({
            recipe: withMeta({ ...structured, unsure: ["title"] }, meta, url),
            extractor,
            usage: null,
          })
        : Effect.fail(failure),
    ),
  );
  return { ...read, raw: text };
});

export const fromWeb = Effect.fn("Web.fromWeb")(function* (url: string) {
  const page = yield* fetchPage(url);
  const read = yield* fromHtml(page.html, page.url);
  return {
    ...read,
    sourceUrl: read.recipe.canonicalUrl ?? page.url,
  } satisfies Imported;
});
