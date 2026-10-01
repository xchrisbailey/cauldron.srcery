import { ImportFailureCode, type ImportSource } from "@cauldron/shared";
import { Context, Effect, Layer, Schema } from "effect";
import { type ExtractedRecipe, hasRecipe, type Usage } from "./Extracted.ts";
import { type ExtractError, RecipeExtractor } from "./RecipeExtractor.ts";
import { readRecipeText } from "./textRecipe.ts";

// One importer per source type, behind one interface. Each tries its
// extractors in order, cheapest first, and fails with a typed reason the
// job turns into plain copy.

export class ImportFailed extends Schema.TaggedError<ImportFailed>()("ImportFailed", {
  code: ImportFailureCode,
}) {}

export interface ImportRequest {
  readonly source: ImportSource;
  readonly url: string | null;
  readonly text: string | null;
}

export interface Imported {
  readonly recipe: ExtractedRecipe;
  /** Which extractor read it: "text", "model", and later "json-ld" and "microdata". */
  readonly extractor: string;
  /** What was read, for the job row. */
  readonly raw: string | null;
  readonly usage: Usage | null;
  /** The link to record on the recipe: the page's canonical link when it has one. */
  readonly sourceUrl: string | null;
}

const failed = (code: ImportFailureCode) => new ImportFailed({ code });

const fromExtractError = (error: ExtractError) =>
  failed(error.reason === "timeout" ? "timeout" : "unavailable");

/**
 * Reads a recipe from text: a paste, a page's readable text or a caption.
 * Clearly laid out text is read without a model. Anything else goes to the
 * model, and the rough reading is the fallback when there's no model.
 */
export const fromText = Effect.fn("Importers.fromText")(function* (
  text: string,
  kind: "text" | "caption" | "page",
) {
  const extractor = yield* RecipeExtractor;
  const reading = kind === "page" ? null : readRecipeText(text);
  if (reading?.clarity === "clear") {
    return { recipe: reading.recipe, extractor: "text", usage: null };
  }
  const rough =
    reading && hasRecipe(reading.recipe) ? { recipe: reading.recipe, extractor: "text" } : null;
  if (!extractor.available) {
    if (rough) return { ...rough, usage: null };
    return yield* failed("noRecipe");
  }
  const extraction = yield* extractor.extract({ text, kind }).pipe(
    // The model failed: a rough reading is better than nothing.
    Effect.catchTag("ExtractError", (error) =>
      Effect.logWarning("Model extraction failed", {
        reason: error.reason,
        detail: error.detail,
      }).pipe(Effect.andThen(rough ? Effect.succeed(null) : Effect.fail(fromExtractError(error)))),
    ),
  );
  if (extraction === null) return { ...rough!, usage: null };
  if (extraction.outcome === "inVideo") return yield* failed("spokenOnly");
  if (extraction.outcome === "missing" || !hasRecipe(extraction.recipe)) {
    return yield* failed("noRecipe");
  }
  return { recipe: extraction.recipe, extractor: "model", usage: extraction.usage };
});

export class Importers extends Context.Service<
  Importers,
  { readonly run: (request: ImportRequest) => Effect.Effect<Imported, ImportFailed> }
>()("cauldron/api/Importers") {
  static readonly layer = Layer.effect(
    Importers,
    Effect.gen(function* () {
      const context = yield* Effect.context<RecipeExtractor>();
      return Importers.of({
        run: Effect.fn("Importers.run")(function* (request) {
          if (request.text !== null) {
            const read = yield* fromText(request.text, "text");
            return { ...read, raw: null, sourceUrl: null };
          }
          // Links are read by the website (#14) and social (#16) importers.
          return yield* failed("couldntRead");
        }, Effect.provideContext(context)),
      });
    }),
  );
}
