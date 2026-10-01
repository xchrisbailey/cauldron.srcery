import type { Macros } from "@cauldron/shared";
import { emptyExtracted, type ExtractedRecipe, type ExtractedStep } from "./Extracted.ts";
import { absolute, type HtmlDocument, plainText } from "./html.ts";

// schema.org Recipe data, which most recipe sites publish for search engines:
// JSON-LD first, microdata second. Mapped straight to a draft, no model.

type Json = unknown;
type Node = Record<string, Json>;

const isNode = (value: Json): value is Node =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const list = (value: Json): ReadonlyArray<Json> =>
  value === undefined || value === null ? [] : Array.isArray(value) ? value : [value];

const typesOf = (node: Node) => list(node["@type"]).map((t) => String(t).replace(/^.*[/:]/, ""));

/** A text value: a string, a number, or a node's name or text. */
const textOf = (value: Json): string | null => {
  if (typeof value === "string") return plainText(value) || null;
  if (typeof value === "number") return String(value);
  if (Array.isArray(value)) return textOf(value[0]);
  if (isNode(value)) return textOf(value["name"] ?? value["text"] ?? value["@value"]);
  return null;
};

/** Minutes in an ISO 8601 duration ("PT1H20M", "P0DT45M") or a plain "45 minutes". */
export const isoMinutes = (value: Json): number | null => {
  const text = textOf(value);
  // Durations are short; a long string is junk, and bounds the regexes below.
  if (!text || text.length > 64) return null;
  const iso =
    /^P(?:(\d+(?:\.\d+)?)Y)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)W)?(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$/i.exec(
      text.trim(),
    );
  if (iso) {
    const [, , , weeks, days, hours, minutes, seconds] = iso.map((n) => Number(n ?? 0));
    const total = (weeks! * 7 + days!) * 1440 + hours! * 60 + minutes! + seconds! / 60;
    return Number.isFinite(total) && total > 0 ? Math.round(total) : null;
  }
  const hours = /(?<!\d)(\d{1,3}(?:\.\d{1,2})?)\s*(?:h|hr|hrs|hours?)\b/i.exec(text);
  const minutes = /(?<!\d)(\d{1,4})\s*(?:m|min|mins|minutes?)\b/i.exec(text);
  if (!hours && !minutes) return null;
  return Math.round(Number(hours?.[1] ?? 0) * 60 + Number(minutes?.[1] ?? 0)) || null;
};

/** "4 servings", ["4", "4 servings"], 6 or "Makes 12" → the first whole number. */
const servingsOf = (value: Json): number | null => {
  for (const item of list(value)) {
    const text = textOf(item);
    const n = text ? /(\d+)/.exec(text)?.[1] : undefined;
    if (n) return Number(n);
  }
  return null;
};

/** "240 calories", "12 g", 12 → the number. Anything else is unknown. */
const amountOf = (value: Json): number | null => {
  const text = textOf(value);
  if (!text || text.length > 64) return null;
  // "1,200 kcal" has a thousands comma; "12,5 g" has a decimal one.
  const n = /(\d+(?:[.,]\d+)?)/.exec(text.replace(/(\d),(?=\d{3}(?!\d))/g, "$1"))?.[1];
  if (n === undefined) return null;
  const amount = Number(n.replace(",", "."));
  return Number.isFinite(amount) ? amount : null;
};

/** schema.org NutritionInformation, which is per serving. */
export const macrosOf = (value: Json): Macros | undefined => {
  const node = list(value).find(isNode);
  if (!node) return undefined;
  const macros = {
    calories: amountOf(node["calories"]),
    protein: amountOf(node["proteinContent"]),
    carbs: amountOf(node["carbohydrateContent"]),
    fat: amountOf(node["fatContent"]),
  };
  return Object.values(macros).some((v) => v !== null) ? macros : undefined;
};

const namesOf = (value: Json): string | null => {
  const names = list(value)
    .map(textOf)
    .filter((n): n is string => n !== null && n !== "");
  return names.length > 0 ? names.join(", ") : null;
};

const imageOf = (value: Json, base: string): string | null => {
  for (const item of list(value)) {
    const url =
      typeof item === "string" ? item : isNode(item) ? (item["url"] ?? item["contentUrl"]) : null;
    const resolved = typeof url === "string" ? absolute(url, base) : null;
    if (resolved) return resolved;
  }
  return null;
};

/** Steps from a string, a list of strings, HowToSteps, or HowToSections of them. */
const stepsOf = (value: Json, section: string | null = null): Array<ExtractedStep> => {
  const out: Array<ExtractedStep> = [];
  for (const item of list(value)) {
    if (typeof item === "string") {
      // One string can hold the whole method, one step per line.
      for (const part of item.split(/\n+|<br\s*\/?>|<\/p>\s*<p>/i)) {
        const text = plainText(part).replace(/^\d{1,2}[.)]\s+/, "");
        if (text) out.push({ text, section, unsure: false });
      }
      continue;
    }
    if (!isNode(item)) continue;
    const types = typesOf(item);
    if (types.includes("HowToSection") || item["itemListElement"] !== undefined) {
      const name = textOf(item["name"]);
      out.push(...stepsOf(item["itemListElement"], name ?? section));
      continue;
    }
    const text = textOf(item["text"]) ?? textOf(item["name"]) ?? textOf(item["description"]);
    if (text) out.push({ text, section, unsure: false });
  }
  return out;
};

const TAG_FIELDS = ["recipeCuisine", "recipeCategory"] as const;

const fromRecipeNode = (node: Node, base: string): ExtractedRecipe => {
  const ingredients = list(node["recipeIngredient"] ?? node["ingredients"])
    .map(textOf)
    .filter((l): l is string => l !== null && l !== "")
    // WP Recipe Maker wraps notes twice: "4 thighs ((Note 1))".
    .map((line) => ({
      line: line.replace(/\(\(([^()]*)\)\)/g, "($1)"),
      section: null,
      unsure: false,
    }));
  const tags = TAG_FIELDS.flatMap((field) =>
    list(node[field]).flatMap((value) =>
      (textOf(value) ?? "")
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean),
    ),
  );
  const prepMinutes = isoMinutes(node["prepTime"]);
  const cookMinutes = isoMinutes(node["cookTime"]);
  const macros = macrosOf(node["nutrition"]);
  return {
    ...emptyExtracted,
    title: textOf(node["name"]) ?? textOf(node["headline"]),
    description: textOf(node["description"]),
    servings: servingsOf(node["recipeYield"] ?? node["yield"]),
    prepMinutes,
    cookMinutes,
    totalMinutes: isoMinutes(node["totalTime"]),
    ...(macros === undefined ? {} : { macros }),
    author: namesOf(node["author"]),
    siteName: namesOf(node["publisher"]),
    canonicalUrl: typeof node["url"] === "string" ? absolute(node["url"], base) : null,
    imageUrl: imageOf(node["image"] ?? node["thumbnailUrl"], base),
    tags,
    ingredients,
    steps: stepsOf(node["recipeInstructions"]),
  };
};

/** Every node in a JSON-LD value: top level, arrays, @graph and nested values. */
function* nodes(value: Json, depth = 0): Generator<Node> {
  if (depth > 6) return;
  for (const item of list(value)) {
    if (!isNode(item)) continue;
    yield item;
    for (const key of ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"]) {
      if (item[key] !== undefined) yield* nodes(item[key], depth + 1);
    }
  }
}

/** No recipe's JSON-LD comes near this; anything bigger isn't parsed. */
const JSON_LD_MAX = 1024 * 1024;

const parseJson = (text: string): Json => {
  if (text.length > JSON_LD_MAX) return null;
  const cleaned = text
    .replace(/^\s*<!\[CDATA\[|\]\]>\s*$/g, "")
    // [ \t], not \s: \s also matches newlines, which makes this quadratic.
    .replace(/^[ \t]*\/\/.*$/gm, "")
    .trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    // Some sites put raw line breaks inside strings.
    try {
      return JSON.parse(cleaned.replace(/[\n\r\t]+/g, " "));
    } catch {
      return null;
    }
  }
};

/** The page's JSON-LD Recipe, or null. When there are several, the one with the most ingredients. */
export const jsonLdRecipe = (document: HtmlDocument, base: string): ExtractedRecipe | null => {
  let best: ExtractedRecipe | null = null;
  for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
    for (const node of nodes(parseJson(script.textContent ?? ""))) {
      if (!typesOf(node).includes("Recipe")) continue;
      const recipe = fromRecipeNode(node, base);
      if (!best || recipe.ingredients.length > best.ingredients.length) best = recipe;
    }
  }
  return best;
};

// ---------------------------------------------------------------------------
// Microdata

type El = NonNullable<ReturnType<HtmlDocument["querySelector"]>>;

/** Elements with an itemprop inside `scope`, not inside a nested item. */
const props = (scope: El, name: string): Array<El> =>
  [...scope.querySelectorAll(`[itemprop~="${name}"]`)].filter(
    (el) =>
      el.parentElement?.closest("[itemscope]") === scope || el.closest("[itemscope]") === scope,
  );

const valueOf = (el: El): string | null => {
  const raw =
    el.getAttribute("content") ??
    el.getAttribute("datetime") ??
    (el.tagName === "META" ? null : el.textContent);
  return raw ? plainText(raw) || null : null;
};

const first = (scope: El, name: string) => {
  for (const el of props(scope, name)) {
    const value = valueOf(el);
    if (value) return value;
  }
  return null;
};

export const microdataRecipe = (document: HtmlDocument, base: string): ExtractedRecipe | null => {
  const scope = [...document.querySelectorAll("[itemscope][itemtype]")].find((el) =>
    /schema\.org\/Recipe\b/i.test(el.getAttribute("itemtype") ?? ""),
  );
  if (!scope) return null;
  const ingredients = [...props(scope, "recipeIngredient"), ...props(scope, "ingredients")]
    .map(valueOf)
    .filter((l): l is string => l !== null)
    .map((line) => ({ line, section: null, unsure: false }));
  const steps: Array<ExtractedStep> = [];
  for (const el of props(scope, "recipeInstructions")) {
    const items = el.querySelectorAll("li");
    if (items.length > 0) {
      for (const li of items) {
        const text = plainText(li.textContent ?? "");
        if (text) steps.push({ text, section: null, unsure: false });
      }
    } else {
      // Paragraphs and line breaks split steps; source newlines are just
      // pretty-printing.
      for (const part of el.innerHTML.split(/<br\s*\/?>|<\/p>|<\/div>/i)) {
        const text = plainText(part);
        if (text) steps.push({ text, section: null, unsure: false });
      }
    }
  }
  const image = props(scope, "image")[0];
  const author = props(scope, "author")[0];
  return {
    ...emptyExtracted,
    title: first(scope, "name"),
    description: first(scope, "description"),
    servings: servingsOf(first(scope, "recipeYield")),
    prepMinutes: isoMinutes(first(scope, "prepTime")),
    cookMinutes: isoMinutes(first(scope, "cookTime")),
    totalMinutes: isoMinutes(first(scope, "totalTime")),
    author: author
      ? author.hasAttribute("itemscope")
        ? first(author, "name")
        : valueOf(author)
      : null,
    imageUrl: image
      ? absolute(
          image.getAttribute("src") ?? image.getAttribute("content") ?? image.getAttribute("href"),
          base,
        )
      : null,
    tags: [first(scope, "recipeCuisine"), first(scope, "recipeCategory")].filter(
      (t): t is string => t !== null,
    ),
    ingredients,
    steps,
  };
};
