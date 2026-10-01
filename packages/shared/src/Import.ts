import { Schema } from "effect";
import { validation } from "./copy.ts";
import { Macros, RecipeId, SourceUrl } from "./Recipe.ts";

// Distill (#13): a link or pasted text becomes a draft recipe, which the cook
// reviews in the editor before anything is saved.

export const ImportId = Schema.String.check(Schema.isUUID()).pipe(Schema.brand("ImportId"));
export type ImportId = typeof ImportId.Type;

/** Where an import came from. A subset of `SourcePlatform`: never "manual". */
export const ImportSource = Schema.Literals(["web", "instagram", "tiktok", "text"]);
export type ImportSource = typeof ImportSource.Type;

export const ImportStatus = Schema.Literals([
  "queued",
  "running",
  "done",
  "failed",
  "cancelled",
  "saved",
]);
export type ImportStatus = typeof ImportStatus.Type;

/** Pasted text: about 20 pages, far more than any recipe. */
export const IMPORT_TEXT_MAX = 50_000;

/** Exactly one of a link or pasted text. */
export const ImportInput = Schema.Struct({
  url: Schema.optionalKey(SourceUrl),
  text: Schema.optionalKey(
    Schema.Trim.check(
      Schema.isNonEmpty({ message: validation.required.text }),
      Schema.isMaxLength(IMPORT_TEXT_MAX, {
        message: validation.tooLong(IMPORT_TEXT_MAX).text,
      }),
    ),
  ),
}).check(
  Schema.makeFilter<{ readonly url?: string; readonly text?: string }>((input) =>
    (input.url === undefined) !== (input.text === undefined) ? undefined : validation.required.text,
  ),
);
export type ImportInput = typeof ImportInput.Type;

/** Top-level draft fields an importer can flag as unsure, shown in the Tips color. */
export const DraftField = Schema.Literals([
  "title",
  "description",
  "servings",
  "prepMinutes",
  "cookMinutes",
  "totalMinutes",
  "macros",
  "sourceUrl",
  "tags",
  "notes",
]);
export type DraftField = typeof DraftField.Type;

export const DraftIngredient = Schema.Struct({
  /** The line as the source wrote it. The editor reads it with the shared line parser. */
  line: Schema.String,
  section: Schema.NullOr(Schema.String),
  /** The importer isn't sure it read this line right. */
  unsure: Schema.Boolean,
});
export type DraftIngredient = typeof DraftIngredient.Type;

export const DraftStep = Schema.Struct({
  text: Schema.String,
  section: Schema.NullOr(Schema.String),
  unsure: Schema.Boolean,
});
export type DraftStep = typeof DraftStep.Type;

/**
 * A recipe as an importer read it, ready to open in the editor. Values are
 * already trimmed to `RECIPE_LIMITS`, but nothing here is validated as a
 * recipe until the cook saves it.
 */
export const ImportDraft = Schema.Struct({
  title: Schema.String,
  description: Schema.NullOr(Schema.String),
  servings: Schema.NullOr(Schema.Int),
  prepMinutes: Schema.NullOr(Schema.Int),
  cookMinutes: Schema.NullOr(Schema.Int),
  totalMinutes: Schema.NullOr(Schema.Int),
  /** Per serving, when the source published it. */
  macros: Schema.optionalKey(Macros),
  sourcePlatform: ImportSource,
  sourceUrl: Schema.NullOr(Schema.String),
  sourceAuthor: Schema.NullOr(Schema.String),
  /** The site or account the recipe came from, for attribution. */
  siteName: Schema.NullOr(Schema.String),
  notes: Schema.NullOr(Schema.String),
  /** A cover photo the importer fetched, already in the photos table. */
  photoKey: Schema.NullOr(Schema.String),
  tags: Schema.Array(Schema.String),
  ingredients: Schema.Array(DraftIngredient),
  steps: Schema.Array(DraftStep),
  /** Fields to confirm before saving. */
  unsure: Schema.Array(DraftField),
});
export type ImportDraft = typeof ImportDraft.Type;

/** Why an import failed. Each has a plain message in `copy.imports`. */
export const ImportFailureCode = Schema.Literals([
  "couldntRead",
  "noRecipe",
  "spokenOnly",
  "tooLarge",
  "blocked",
  "timeout",
  "unavailable",
]);
export type ImportFailureCode = typeof ImportFailureCode.Type;

export const ImportFailure = Schema.Struct({
  code: ImportFailureCode,
  message: Schema.String,
});
export type ImportFailure = typeof ImportFailure.Type;

export class ImportJob extends Schema.Class<ImportJob>("ImportJob")({
  id: ImportId,
  status: ImportStatus,
  source: ImportSource,
  sourceUrl: Schema.NullOr(Schema.String),
  /** Set when the job is done. */
  draft: Schema.NullOr(ImportDraft),
  /** Set when the job failed. */
  failure: Schema.NullOr(ImportFailure),
  /** A live recipe already in the box from the same link. */
  duplicateOf: Schema.NullOr(Schema.Struct({ id: RecipeId, title: Schema.String })),
  /** The recipe the draft was saved as. */
  recipeId: Schema.NullOr(RecipeId),
  createdAt: Schema.Date,
  updatedAt: Schema.Date,
}) {}

/** Statuses a job can still change from. */
export const isImportPending = (status: ImportStatus) =>
  status === "queued" || status === "running";
