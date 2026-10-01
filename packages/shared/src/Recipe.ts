import { Schema } from "effect";
import { validation } from "./copy.ts";
import { AltMeasure, Quantity, UnitCode } from "./ingredients/schema.ts";
import { PageQuery } from "./Pagination.ts";

// The recipe domain as the API sends and receives it. The web editor validates
// the same input schemas through Standard Schema, so the limits live here once.

export const RecipeId = Schema.String.check(Schema.isUUID()).pipe(Schema.brand("RecipeId"));
export type RecipeId = typeof RecipeId.Type;

export const TagId = Schema.String.check(Schema.isUUID()).pipe(Schema.brand("TagId"));
export type TagId = typeof TagId.Type;

export const RECIPE_LIMITS = {
  title: 200,
  description: 2000,
  notes: 20000,
  url: 2048,
  author: 200,
  section: 200,
  item: 500,
  note: 500,
  line: 1000,
  step: 5000,
  tag: 40,
  tags: 30,
  ingredients: 300,
  steps: 200,
  servings: 1000,
  /** Two weeks, enough for a long ferment. */
  minutes: 60 * 24 * 14,
  timerSeconds: 60 * 60 * 72,
  /** Per serving. */
  calories: 20000,
  /** Grams of protein, carbs or fat per serving. */
  grams: 2000,
} as const;

/** Trimmed, non-empty text of at most `max` characters. */
const Text = (max: number) =>
  Schema.Trim.check(
    Schema.isNonEmpty({ message: validation.required.text }),
    Schema.isMaxLength(max, { message: validation.tooLong(max).text }),
  );

/** Optional trimmed text. The server stores a blank string as null. */
const OptionalText = (max: number) =>
  Schema.NullOr(
    Schema.Trim.check(Schema.isMaxLength(max, { message: validation.tooLong(max).text })),
  );

const WholeNumber = (minimum: number, maximum: number) =>
  Schema.Int.annotate({ message: validation.wholeNumber(minimum, maximum).text }).check(
    Schema.isBetween(
      { minimum, maximum },
      { message: validation.wholeNumber(minimum, maximum).text },
    ),
  );

const List = <S extends Schema.Top>(item: S, max: number) =>
  Schema.Array(item).check(Schema.isMaxLength(max, { message: validation.tooMany(max).text }));

const Minutes = Schema.NullOr(WholeNumber(0, RECIPE_LIMITS.minutes));

const Grams = Schema.Finite.annotate({
  message: validation.numberBetween(0, RECIPE_LIMITS.grams).text,
}).check(
  Schema.isBetween(
    { minimum: 0, maximum: RECIPE_LIMITS.grams },
    { message: validation.numberBetween(0, RECIPE_LIMITS.grams).text },
  ),
);

/**
 * Calories and macros for one serving, as written on the recipe or entered by
 * hand. Any of them can be unknown. The tracker (#23) may later compute these
 * from the ingredients instead.
 */
export const MacrosInput = Schema.Struct({
  calories: Schema.NullOr(WholeNumber(0, RECIPE_LIMITS.calories)),
  protein: Schema.NullOr(Grams),
  carbs: Schema.NullOr(Grams),
  fat: Schema.NullOr(Grams),
});
export type MacrosInput = typeof MacrosInput.Type;

export const Macros = Schema.Struct({
  calories: Schema.NullOr(Schema.Number),
  protein: Schema.NullOr(Schema.Number),
  carbs: Schema.NullOr(Schema.Number),
  fat: Schema.NullOr(Schema.Number),
}).annotate({ identifier: "Macros" });
export type Macros = typeof Macros.Type;

export const MACRO_KEYS = ["calories", "protein", "carbs", "fat"] as const;
export type MacroKey = (typeof MACRO_KEYS)[number];

export const noMacros: Macros = { calories: null, protein: null, carbs: null, fat: null };

/** What a model needs to estimate a recipe's macros: its ingredient lines and yield. */
export const MacroEstimateInput = Schema.Struct({
  title: Schema.NullOr(Schema.Trim.check(Schema.isMaxLength(RECIPE_LIMITS.title))),
  servings: Schema.NullOr(WholeNumber(1, RECIPE_LIMITS.servings)),
  ingredients: Schema.Array(Text(RECIPE_LIMITS.line)).check(
    Schema.isMinLength(1, { message: validation.required.text }),
    Schema.isMaxLength(RECIPE_LIMITS.ingredients, {
      message: validation.tooMany(RECIPE_LIMITS.ingredients).text,
    }),
  ),
});
export type MacroEstimateInput = typeof MacroEstimateInput.Type;

export const SourcePlatform = Schema.Literals(["web", "instagram", "tiktok", "manual", "text"]);
export type SourcePlatform = typeof SourcePlatform.Type;

export const TagKind = Schema.Literals(["cuisine", "meal", "diet", "other"]);
export type TagKind = typeof TagKind.Type;

/** A web link: http or https only. */
export const SourceUrl = Schema.Trim.check(
  Schema.isMaxLength(RECIPE_LIMITS.url, { message: validation.tooLong(RECIPE_LIMITS.url).text }),
  Schema.isPattern(/^https?:\/\/[^\s/]+\S*$/i, { message: validation.link.text }),
);

export const TagName = Text(RECIPE_LIMITS.tag);

/** One ingredient line, already parsed (by the shared line parser) and possibly corrected. */
export const IngredientInput = Schema.Struct({
  /** Heading this line sits under, e.g. "For the sauce". */
  section: OptionalText(RECIPE_LIMITS.section),
  quantity: Schema.NullOr(Quantity),
  unit: Schema.NullOr(UnitCode),
  item: Text(RECIPE_LIMITS.item),
  note: OptionalText(RECIPE_LIMITS.note),
  optional: Schema.Boolean,
  alt: Schema.NullOr(AltMeasure),
  /** The line exactly as written. */
  original: Text(RECIPE_LIMITS.line),
});
export type IngredientInput = typeof IngredientInput.Type;

export const StepInput = Schema.Struct({
  section: OptionalText(RECIPE_LIMITS.section),
  text: Text(RECIPE_LIMITS.step),
  timerSeconds: Schema.NullOr(WholeNumber(1, RECIPE_LIMITS.timerSeconds)),
});
export type StepInput = typeof StepInput.Type;

/** Everything a recipe is made of. Create and update both send the whole recipe. */
export const RecipeInput = Schema.Struct({
  title: Text(RECIPE_LIMITS.title),
  description: OptionalText(RECIPE_LIMITS.description),
  servings: Schema.NullOr(WholeNumber(1, RECIPE_LIMITS.servings)),
  prepMinutes: Minutes,
  cookMinutes: Minutes,
  totalMinutes: Minutes,
  sourcePlatform: SourcePlatform,
  sourceUrl: Schema.NullOr(SourceUrl),
  sourceAuthor: OptionalText(RECIPE_LIMITS.author),
  notes: OptionalText(RECIPE_LIMITS.notes),
  /** The cover photo's id from the photos API (#12), or null for none. */
  photoKey: Schema.NullOr(Schema.String.check(Schema.isUUID())),
  /** Per serving. Left out, an update keeps what the recipe had. */
  macros: Schema.optionalKey(MacrosInput),
  tags: List(TagName, RECIPE_LIMITS.tags),
  ingredients: List(IngredientInput, RECIPE_LIMITS.ingredients),
  steps: List(StepInput, RECIPE_LIMITS.steps),
});
export type RecipeInput = typeof RecipeInput.Type;

export class Tag extends Schema.Class<Tag>("Tag")({
  id: TagId,
  name: Schema.String,
  kind: TagKind,
}) {}

export class TagWithCount extends Schema.Class<TagWithCount>("TagWithCount")({
  id: TagId,
  name: Schema.String,
  kind: TagKind,
  /** Live (not deleted) recipes with this tag. */
  recipeCount: Schema.Int,
}) {}

export const TagUpdate = Schema.Struct({ name: TagName });
export type TagUpdate = typeof TagUpdate.Type;

export const Ingredient = Schema.Struct({
  ...IngredientInput.fields,
  item: Schema.String,
  original: Schema.String,
  section: Schema.NullOr(Schema.String),
  note: Schema.NullOr(Schema.String),
  /** Normalized merge key (see `ingredientKey`). */
  itemKey: Schema.String,
});
export type Ingredient = typeof Ingredient.Type;

export const Step = Schema.Struct({
  section: Schema.NullOr(Schema.String),
  text: Schema.String,
  timerSeconds: Schema.NullOr(Schema.Int),
});
export type Step = typeof Step.Type;

/** Whether `YYYY-MM-DD` names a day that exists (no February 31st). */
export const isRealDate = (value: string): boolean => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
};

/** A calendar day, `YYYY-MM-DD`. */
export const LocalDate = Schema.String.check(
  Schema.makeFilter<string>((value) => (isRealDate(value) ? undefined : validation.date.text)),
);
export type LocalDate = typeof LocalDate.Type;

const RecipeFields = {
  id: RecipeId,
  title: Schema.String,
  description: Schema.NullOr(Schema.String),
  servings: Schema.NullOr(Schema.Int),
  prepMinutes: Schema.NullOr(Schema.Int),
  cookMinutes: Schema.NullOr(Schema.Int),
  totalMinutes: Schema.NullOr(Schema.Int),
  /** The cover photo's id; show it with `photoUrl(photoKey, variant)`. */
  photoKey: Schema.NullOr(Schema.String),
  /** Per serving. */
  macros: Macros,
  tags: Schema.Array(Tag),
  lastCookedOn: Schema.NullOr(LocalDate),
  createdAt: Schema.Date,
  updatedAt: Schema.Date,
};

/** What the library lists: enough for a card. */
export class RecipeSummary extends Schema.Class<RecipeSummary>("RecipeSummary")(RecipeFields) {}

export class Recipe extends Schema.Class<Recipe>("Recipe")({
  ...RecipeFields,
  sourcePlatform: SourcePlatform,
  sourceUrl: Schema.NullOr(Schema.String),
  sourceAuthor: Schema.NullOr(Schema.String),
  notes: Schema.NullOr(Schema.String),
  ingredients: Schema.Array(Ingredient),
  steps: Schema.Array(Step),
  /** Set while the recipe is banished (soft deleted) and can still be restored. */
  deletedAt: Schema.NullOr(Schema.Date),
}) {}

export const RecipeSort = Schema.Literals(["recent", "title", "lastCooked"]);
export type RecipeSort = typeof RecipeSort.Type;

export const RECIPE_SEARCH_MAX = 200;

/** Query string for the recipe list. `q` filters by title, tag and ingredient. */
export const RecipeListQuery = Schema.Struct({
  ...PageQuery.fields,
  sort: Schema.optionalKey(RecipeSort),
  tag: Schema.optionalKey(TagId),
  q: Schema.optionalKey(Schema.Trim.check(Schema.isMaxLength(RECIPE_SEARCH_MAX))),
});
export type RecipeListQuery = typeof RecipeListQuery.Type;

export const RecipeSearchQuery = Schema.Struct({
  q: Schema.Trim.check(Schema.isMaxLength(RECIPE_SEARCH_MAX)),
  limit: Schema.optionalKey(
    Schema.NumberFromString.check(Schema.isInt(), Schema.isBetween({ minimum: 1, maximum: 50 })),
  ),
});
export type RecipeSearchQuery = typeof RecipeSearchQuery.Type;

export const CookedInput = Schema.Struct({
  /** The day it was cooked, in the cook's own calendar. */
  on: LocalDate,
});
export type CookedInput = typeof CookedInput.Type;
