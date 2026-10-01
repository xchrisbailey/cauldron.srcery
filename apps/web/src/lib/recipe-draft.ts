import type { RecipeFormValues } from "./recipe-form";

// The Conjure draft, kept in this browser until the recipe is saved. Storage
// can be missing or full (private windows); the editor works without it.

const KEY = "cauldron:conjure-draft";
/** Bump when the form's row shape changes; older drafts are dropped. */
const VERSION = 1;

export const loadDraft = (): RecipeFormValues | null => {
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return null;
    const stored = JSON.parse(raw) as { version?: number; values?: Partial<RecipeFormValues> };
    const draft = stored.version === VERSION ? stored.values : undefined;
    if (!draft) {
      clearDraft();
      return null;
    }
    // Anything that doesn't look like a draft from this version is dropped.
    if (
      typeof draft.title !== "string" ||
      !Array.isArray(draft.ingredients) ||
      !Array.isArray(draft.steps) ||
      !Array.isArray(draft.tags) ||
      ![draft.servings, draft.prepMinutes, draft.cookMinutes, draft.totalMinutes].every(
        (field) => typeof field === "string",
      ) ||
      !draft.ingredients.every(
        (row) => row.kind === "heading" || (typeof row.text === "string" && row.parsed),
      )
    ) {
      clearDraft();
      return null;
    }
    return {
      review: [],
      sourcePlatform: "manual",
      sourceAuthor: null,
      photoKey: null,
      ...draft,
    } as RecipeFormValues;
  } catch {
    return null;
  }
};

export const saveDraft = (values: RecipeFormValues): boolean => {
  try {
    window.localStorage.setItem(KEY, JSON.stringify({ version: VERSION, values }));
    return true;
  } catch {
    return false;
  }
};

export const clearDraft = () => {
  try {
    window.localStorage.removeItem(KEY);
  } catch {
    // Nothing to clear.
  }
};
