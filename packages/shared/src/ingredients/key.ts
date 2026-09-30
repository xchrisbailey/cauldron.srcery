/**
 * Normalized merge key for an ingredient's item text, stored as `item_key` on
 * recipe_ingredient and gather_item. Two lines with the same key are the same
 * thing to buy: "2 Large Eggs" and "egg" both key to "egg".
 *
 * Lowercased, trimmed, whitespace collapsed, size words (large, medium, small,
 * ...) dropped, and the last word singularized. Deliberately simple: it is a
 * merge key, not a display string. The Gather list (#19) merges rows that
 * share a key per unit dimension (volume, mass, count), never across them.
 */

const SIZE_WORDS = new Set([
  "large",
  "medium",
  "small",
  "big",
  "extra-large",
  "extra",
  "jumbo",
  "mini",
]);

/** Words that end in "s" but are already singular, or whose plural is irregular. */
const SINGULAR_EXCEPTIONS: Readonly<Record<string, string>> = {
  hummus: "hummus",
  couscous: "couscous",
  asparagus: "asparagus",
  molasses: "molasses",
  watercress: "watercress",
  swiss: "swiss",
  lemongrass: "lemongrass",
  brussels: "brussels",
  grits: "grits",
  oats: "oats",
  leaves: "leaf",
  loaves: "loaf",
  halves: "half",
  knives: "knife",
  cloves: "clove",
  olives: "olive",
  chives: "chives",
  greens: "greens",
  cookies: "cookie",
  pies: "pie",
  radishes: "radish",
};

function singularize(word: string): string {
  const exact = SINGULAR_EXCEPTIONS[word];
  if (exact !== undefined) return exact;
  if (word.length <= 3) return word;
  if (/[^aeiou]ies$/.test(word)) return `${word.slice(0, -3)}y`;
  if (/(?:[sxz]|ch|sh)es$/.test(word)) return word.slice(0, -2);
  if (word.endsWith("oes")) return word.slice(0, -2);
  if (/(?:ss|us|is)$/.test(word)) return word;
  if (word.endsWith("s")) return word.slice(0, -1);
  return word;
}

export function ingredientKey(item: string): string {
  const words = item
    .toLowerCase()
    .replace(/[()]/g, " ")
    .split(/\s+/)
    .map((w) => w.replace(/^[^a-z0-9]+|[^a-z0-9]+$/g, ""))
    .filter((w) => w !== "" && !SIZE_WORDS.has(w));
  if (words.length === 0) return item.toLowerCase().trim().replace(/\s+/g, " ");
  words[words.length - 1] = singularize(words[words.length - 1]!);
  return words.join(" ");
}
