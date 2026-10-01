import {
  DraftField,
  type ImportDraft,
  type ImportSource,
  parseIngredientLine,
  RECIPE_LIMITS,
} from "@cauldron/shared";
import type { ExtractedRecipe } from "./Extracted.ts";

// Tidies what an extractor read into a draft the editor can open: trimmed,
// cut to the recipe limits, numbers in range, and flags where a cook should
// look before saving.

const text = (value: string | null | undefined, max: number): string | null => {
  const trimmed = value?.replace(/\s+/g, " ").trim() ?? "";
  return trimmed === "" ? null : trimmed.slice(0, max);
};

/** Keeps line breaks, for notes. */
const block = (value: string | null | undefined, max: number): string | null => {
  const trimmed =
    value
      ?.replace(/[ \t]+/g, " ")
      .replace(/\n{3,}/g, "\n\n")
      .trim() ?? "";
  return trimmed === "" ? null : trimmed.slice(0, max);
};

const int = (value: number | null, min: number, max: number) =>
  value === null || !Number.isFinite(value) || value < min || value > max
    ? null
    : Math.round(value);

/** Grams to one decimal place, the precision the recipe stores. */
const grams = (value: number | null) =>
  value === null || !Number.isFinite(value) || value < 0 || value > RECIPE_LIMITS.grams
    ? null
    : Math.round(value * 10) / 10;

const isDraftField = (value: string): value is DraftField =>
  (DraftField.literals as ReadonlyArray<string>).includes(value);

export interface DraftSource {
  readonly source: ImportSource;
  readonly sourceUrl: string | null;
  readonly photoKey: string | null;
}

export const toDraft = (recipe: ExtractedRecipe, from: DraftSource): ImportDraft => {
  const unsure = new Set<DraftField>(recipe.unsure.filter(isDraftField));
  const title = text(recipe.title, RECIPE_LIMITS.title);
  if (title === null) unsure.add("title");

  const ingredients = recipe.ingredients
    .slice(0, RECIPE_LIMITS.ingredients)
    .flatMap((ingredient) => {
      const line = text(ingredient.line, RECIPE_LIMITS.line);
      if (line === null) return [];
      // A line the shared parser reads with no item would fail the editor's
      // check, so it's flagged here as well.
      const parsed = parseIngredientLine(line);
      return [
        {
          line,
          section: text(ingredient.section, RECIPE_LIMITS.section),
          unsure: ingredient.unsure || parsed.item.trim() === "",
        },
      ];
    });

  const steps = recipe.steps.slice(0, RECIPE_LIMITS.steps).flatMap((step) => {
    const stepText = text(step.text, RECIPE_LIMITS.step);
    return stepText === null
      ? []
      : [
          {
            text: stepText,
            section: text(step.section, RECIPE_LIMITS.section),
            unsure: step.unsure,
          },
        ];
  });

  const seen = new Set<string>();
  const tags = recipe.tags.flatMap((tag) => {
    const name = text(tag.replace(/^#/, ""), RECIPE_LIMITS.tag);
    if (name === null || seen.has(name.toLowerCase())) return [];
    seen.add(name.toLowerCase());
    return [name];
  });

  return {
    title: title ?? "",
    description: text(recipe.description, RECIPE_LIMITS.description),
    servings: int(recipe.servings, 1, RECIPE_LIMITS.servings),
    prepMinutes: int(recipe.prepMinutes, 0, RECIPE_LIMITS.minutes),
    cookMinutes: int(recipe.cookMinutes, 0, RECIPE_LIMITS.minutes),
    totalMinutes: int(recipe.totalMinutes, 0, RECIPE_LIMITS.minutes),
    ...(recipe.macros === undefined
      ? {}
      : {
          macros: {
            calories: int(recipe.macros.calories, 0, RECIPE_LIMITS.calories),
            protein: grams(recipe.macros.protein),
            carbs: grams(recipe.macros.carbs),
            fat: grams(recipe.macros.fat),
          },
        }),
    sourcePlatform: from.source,
    sourceUrl: from.sourceUrl?.slice(0, RECIPE_LIMITS.url) ?? null,
    sourceAuthor: text(recipe.author, RECIPE_LIMITS.author),
    siteName: text(recipe.siteName, RECIPE_LIMITS.author),
    notes: block(recipe.notes, RECIPE_LIMITS.notes),
    photoKey: from.photoKey,
    tags: tags.slice(0, RECIPE_LIMITS.tags),
    ingredients,
    steps,
    unsure: DraftField.literals.filter((field) => unsure.has(field)),
  };
};
