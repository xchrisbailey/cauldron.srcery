import type { DraftField } from "@cauldron/shared";

// What every extractor produces, before it's tidied into an `ImportDraft`.
// JSON-LD, the text reader and the model all fill this one shape, so the
// limits, the ingredient parser and the confidence flags are applied once.

export interface ExtractedLine {
  readonly line: string;
  readonly section: string | null;
  readonly unsure: boolean;
}

export interface ExtractedStep {
  readonly text: string;
  readonly section: string | null;
  readonly unsure: boolean;
}

export interface ExtractedRecipe {
  readonly title: string | null;
  readonly description: string | null;
  readonly servings: number | null;
  readonly prepMinutes: number | null;
  readonly cookMinutes: number | null;
  readonly totalMinutes: number | null;
  readonly author: string | null;
  readonly siteName: string | null;
  /** The page's canonical link, when it gives one. */
  readonly canonicalUrl: string | null;
  readonly imageUrl: string | null;
  readonly tags: ReadonlyArray<string>;
  readonly notes: string | null;
  readonly ingredients: ReadonlyArray<ExtractedLine>;
  readonly steps: ReadonlyArray<ExtractedStep>;
  /** Fields the extractor isn't sure about. */
  readonly unsure: ReadonlyArray<DraftField>;
}

export const emptyExtracted: ExtractedRecipe = {
  title: null,
  description: null,
  servings: null,
  prepMinutes: null,
  cookMinutes: null,
  totalMinutes: null,
  author: null,
  siteName: null,
  canonicalUrl: null,
  imageUrl: null,
  tags: [],
  notes: null,
  ingredients: [],
  steps: [],
  unsure: [],
};

/** Enough of a recipe to be worth opening in the editor: some ingredients and some method. */
export const hasRecipe = (recipe: ExtractedRecipe) =>
  recipe.ingredients.length > 0 && recipe.steps.length > 0;

/** Model usage for the job's cost log. */
export interface Usage {
  readonly model: string;
  readonly inputTokens: number;
  readonly outputTokens: number;
}
