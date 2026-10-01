import { Effect } from "effect";
import { hasRecipe } from "./Extracted.ts";
import { type ExtractError, RecipeExtractor } from "./RecipeExtractor.ts";
import { failed } from "./result.ts";
import { readRecipeText } from "./textRecipe.ts";

const fromExtractError = (error: ExtractError) =>
  failed(error.reason === "timeout" ? "timeout" : "unavailable");

/**
 * Reads a recipe from text: a paste, a page's readable text or a caption.
 * Clearly laid out text is read without a model. Anything else goes to the
 * model, and the rough reading is the fallback when there's no model.
 */
export const fromText = Effect.fn("Imports.fromText")(function* (
  text: string,
  kind: "text" | "caption" | "page",
) {
  const extractor = yield* RecipeExtractor;
  const reading = readRecipeText(text);
  // A page's text carries navigation and comments, so it goes to the model
  // even when it reads cleanly.
  if (reading?.clarity === "clear" && kind !== "page") {
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
