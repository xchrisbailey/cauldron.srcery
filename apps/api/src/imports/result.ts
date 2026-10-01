import { ImportFailureCode } from "@cauldron/shared";
import { Schema } from "effect";
import type { ExtractedRecipe, Usage } from "./Extracted.ts";

// What an importer hands back, and how it fails.

export class ImportFailed extends Schema.TaggedError<ImportFailed>()("ImportFailed", {
  code: ImportFailureCode,
}) {}

export interface Imported {
  readonly recipe: ExtractedRecipe;
  /** Which extractor read it: "json-ld", "microdata", "text" or "model". */
  readonly extractor: string;
  /** What was read, for the job row. */
  readonly raw: string | null;
  readonly usage: Usage | null;
  /** The link to record on the recipe: the page's canonical link when it has one. */
  readonly sourceUrl: string | null;
}

export const failed = (code: ImportFailureCode) => new ImportFailed({ code });
