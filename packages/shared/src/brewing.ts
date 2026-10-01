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

/** Start positions where `needle` appears in `haystack` as whole words. */
const findAll = (haystack: ReadonlyArray<string>, needle: ReadonlyArray<string>) => {
  const starts: Array<number> = [];
  if (needle.length === 0) return starts;
  for (let i = 0; i + needle.length <= haystack.length; i++) {
    if (needle.every((word, j) => haystack[i + j] === word)) starts.push(i);
  }
  return starts;
};

/**
 * For each step, the indexes of the ingredients it mentions. A step mentions
 * an ingredient when it names the whole item ("red bell pepper") or its last
 * word ("the pepper"). Longer names claim their words first, so "green
 * onions" doesn't also count as "onions" and "peanut butter" isn't "butter".
 * A last word only counts when no other ingredient sharing it is named in
 * full in that step, so "black pepper" doesn't pull in "red bell pepper".
 */
export function stepIngredients(
  steps: ReadonlyArray<{ readonly text: string }>,
  ingredients: ReadonlyArray<Pick<Ingredient, "itemKey">>,
): ReadonlyArray<ReadonlyArray<number>> {
  const keys = ingredients.map((i) => wordsOf(i.itemKey));
  const longestFirst = keys.map((_, i) => i).sort((a, b) => keys[b]!.length - keys[a]!.length);
  return steps.map((step) => {
    const text = wordsOf(step.text);
    const taken = Array.from({ length: text.length }, () => false);
    const found = new Set<number>();
    for (const i of longestFirst) {
      const key = keys[i]!;
      for (const start of findAll(text, key)) {
        if (taken.slice(start, start + key.length).every(Boolean)) continue;
        found.add(i);
        taken.fill(true, start, start + key.length);
      }
    }
    const namedHeads = new Set([...found].map((i) => keys[i]!.at(-1)));
    keys.forEach((key, i) => {
      const head = key.at(-1);
      if (
        head === undefined ||
        key.length < 2 ||
        head.length < 3 ||
        VAGUE.has(head) ||
        namedHeads.has(head)
      ) {
        return;
      }
      // Only a last word the longer names haven't already claimed.
      if (text.some((word, at) => word === head && !taken[at])) found.add(i);
    });
    return [...found].sort((a, b) => a - b);
  });
}
