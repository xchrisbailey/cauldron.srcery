import type { RecipeFormValues } from "./recipe-form";

// The Conjure draft, kept in this browser until the recipe is saved. Storage
// can be missing or full (private windows); the editor works without it.

const KEY = "cauldron:conjure-draft";

export const loadDraft = (): RecipeFormValues | null => {
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return null;
    const draft = JSON.parse(raw) as Partial<RecipeFormValues>;
    // Anything that doesn't look like a draft from this version is dropped.
    if (
      typeof draft.title !== "string" ||
      !Array.isArray(draft.ingredients) ||
      !Array.isArray(draft.steps) ||
      !Array.isArray(draft.tags)
    ) {
      return null;
    }
    return {
      review: [],
      sourcePlatform: "manual",
      sourceAuthor: null,
      ...draft,
    } as RecipeFormValues;
  } catch {
    return null;
  }
};

export const saveDraft = (values: RecipeFormValues): boolean => {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(values));
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
