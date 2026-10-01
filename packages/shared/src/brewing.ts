import type { Ingredient } from "./Recipe.ts";
import { singularize } from "./ingredients/key.ts";

// Start brewing (#20): which ingredients each method step uses, so cook mode
// can show them with the step.

/** Words that name a part of nearly anything and so can't identify an ingredient alone. */
const VAGUE = new Set(["juice", "zest", "leaf", "powder", "seed", "sauce", "stock", "water"]);

const wordsOf = (text: string) =>
  text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s-]/gu, " ")
    .split(/\s+/)
    .filter(Boolean)
    .map(singularize);

const contains = (haystack: ReadonlyArray<string>, needle: ReadonlyArray<string>) => {
  if (needle.length === 0) return false;
  for (let i = 0; i + needle.length <= haystack.length; i++) {
    if (needle.every((word, j) => haystack[i + j] === word)) return true;
  }
  return false;
};

/**
 * For each step, the indexes of the ingredients it mentions. A step mentions
 * an ingredient when it names the whole item ("red bell pepper") or its last
 * word ("the pepper"). A last word only counts when no other ingredient
 * sharing it is named in full in that step, so "black pepper" in a step
 * doesn't pull in "red bell pepper" too.
 */
export function stepIngredients(
  steps: ReadonlyArray<{ readonly text: string }>,
  ingredients: ReadonlyArray<Pick<Ingredient, "itemKey">>,
): ReadonlyArray<ReadonlyArray<number>> {
  const keys = ingredients.map((i) => wordsOf(i.itemKey));
  return steps.map((step) => {
    const text = wordsOf(step.text);
    const full = new Set<number>();
    keys.forEach((key, i) => {
      if (contains(text, key)) full.add(i);
    });
    const namedHeads = new Set([...full].map((i) => keys[i]!.at(-1)));
    const found = new Set(full);
    keys.forEach((key, i) => {
      const head = key.at(-1);
      if (
        head !== undefined &&
        key.length > 1 &&
        head.length >= 3 &&
        !VAGUE.has(head) &&
        !namedHeads.has(head) &&
        text.includes(head)
      ) {
        found.add(i);
      }
    });
    return [...found].sort((a, b) => a - b);
  });
}
