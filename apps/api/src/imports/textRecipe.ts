import { detectTimer, isSectionHeading, parseIngredientLine } from "@cauldron/shared";
import {
  emptyExtracted,
  type ExtractedLine,
  type ExtractedRecipe,
  type ExtractedStep,
} from "./Extracted.ts";

// Reads a recipe out of plain text without a model: a paste, or a caption.
// Most recipes people paste are laid out with an "Ingredients" heading and a
// "Method" heading, and those read reliably here at no cost. Text without
// those headings gets a rougher reading, flagged for review, that importers
// only use when no model is available.

export type Clarity = "clear" | "rough";

export interface TextReading {
  readonly clarity: Clarity;
  readonly recipe: ExtractedRecipe;
}

// Decoration around a heading: markdown, bullets, emoji, trailing colons.
const DECORATION =
  /^[\s#*_>•\-–—=~|▢□◦‣\p{Extended_Pictographic}️‍]+|[\s#*_:：=~|\p{Extended_Pictographic}️‍]+$/gu;
const bare = (line: string) => line.replace(DECORATION, "").trim();

const INGREDIENTS_HEADING =
  /^(?:the\s+)?(?:ingredients?(?:\s+list)?|what\s+you(?:'|’)?ll\s+need|what\s+you\s+need|you(?:'|’)?ll\s+need|you\s+will\s+need|shopping\s+list|for\s+the\s+recipe)$/i;
const METHOD_HEADING =
  /^(?:the\s+)?(?:method|directions?|instructions?|steps?|preparation|prep(?:aration)?\s+steps?|how\s+to\s+(?:make|cook)(?:\s+(?:it|this|them))?|to\s+make|recipe\s+steps?)$/i;
const NOTES_HEADING =
  /^(?:notes?|tips?|cook(?:'|’)?s\s+notes?|recipe\s+notes?|storage|to\s+store|make\s+ahead|substitutions?|variations?)$/i;

// "Ingredients: 2 eggs, flour" puts content on the heading line itself.
const INLINE_HEADING = /^([^:：]{3,40})[:：]\s*(.+)$/;

const BULLET = /^\s*(?:[-•*▢□◦‣–—]|\d{1,2}[.)](?=\s)|step\s*\d{1,2}\s*[.:)-]?)\s*/i;
const HASHTAGS = /(?:^|\s)#[\p{L}\p{N}_]+/gu;

const SERVINGS =
  /^(?:serves|servings?|yield|yields|makes|portions?)\s*[:：-]?\s*(?:about\s+)?(\d{1,3})(?:\s*(?:-|–|to)\s*\d{1,3})?\b/i;
const SERVINGS_AFTER = /^(\d{1,3})(?:\s*(?:-|–|to)\s*\d{1,3})?\s+(?:servings?|portions?|people)\b/i;
const TIME =
  /^(prep(?:aration)?|cook(?:ing)?|bake|baking|total|ready\s+in)(?:\s+time)?\s*[:：-]?\s*(.+)$/i;

// What is left of a time line once the label is gone: only a duration.
const DURATION =
  /^(?:about\s+|approx\.?\s+)?[\d½¼¾.,\s\-–]+(?:\s*(?:hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|and|to)\b[\d½¼¾.,\s\-–]*)*$/i;

/** Minutes in a duration like "1 hr 20 mins", or null. */
export const parseMinutes = (text: string): number | null => {
  const seconds = detectTimer(text);
  return seconds === null ? null : Math.round(seconds / 60);
};

interface Meta {
  servings: number | null;
  prepMinutes: number | null;
  cookMinutes: number | null;
  totalMinutes: number | null;
}

/** Reads a "Serves 4" or "Prep: 10 min" line into `meta`. True when it was one. */
const readMeta = (line: string, meta: Meta): boolean => {
  // "Prep 10 min | Cook 20 min" packs several on one line.
  const parts = line.split(/\s*[|•·,;]\s*/).filter((p) => p !== "");
  let matched = 0;
  for (const part of parts) {
    const text = bare(part);
    const servings = SERVINGS.exec(text) ?? SERVINGS_AFTER.exec(text);
    if (servings) {
      meta.servings ??= Number(servings[1]);
      matched++;
      continue;
    }
    const time = TIME.exec(text);
    // "Bake at 200C for 10 minutes." is a step; "Bake: 10 minutes" is metadata.
    const minutes = time && DURATION.test(time[2]!) ? parseMinutes(time[2]!) : null;
    if (time && minutes !== null) {
      const kind = time[1]!.toLowerCase();
      if (kind.startsWith("prep")) meta.prepMinutes ??= minutes;
      else if (kind.startsWith("total") || kind.startsWith("ready")) meta.totalMinutes ??= minutes;
      else meta.cookMinutes ??= minutes;
      matched++;
    }
  }
  return matched > 0 && matched === parts.length;
};

type Block = "intro" | "ingredients" | "method" | "notes";

const headingOf = (line: string): Exclude<Block, "intro"> | null => {
  const text = bare(line);
  if (INGREDIENTS_HEADING.test(text)) return "ingredients";
  if (METHOD_HEADING.test(text)) return "method";
  if (NOTES_HEADING.test(text)) return "notes";
  return null;
};

/** A line that reads as an ingredient: it starts with an amount, or is short with no sentence in it. */
const looksLikeIngredient = (line: string) => {
  const parsed = parseIngredientLine(line);
  if (parsed.quantity !== null) return true;
  return /^(?:salt|pepper|oil|water|a\s+(?:pinch|handful|splash|knob|drizzle)|juice\s+of|zest\s+of|zest|pinch\s+of)\b/i.test(
    line,
  );
};

const clean = (line: string) => line.replace(HASHTAGS, " ").replace(/\s+/g, " ").trim();

// Sign-offs and blog calls to action after the last step.
const TRAILER =
  /^(?:love\b|cheers\b|thanks\b|regards\b|best\s*,|xx?o?\b|enjoy\b|did\s+you\s+make|tag\s+me|follow\s+me|let\s+me\s+know|leave\s+a\s+(?:comment|review))/i;

/** Splits a method block into steps: numbered steps, then blank lines, then one per line. */
const splitSteps = (lines: ReadonlyArray<string>): Array<string> => {
  const steps: Array<string> = [];
  const numbered = lines.filter((l) => /^\s*(?:\d{1,2}[.)]|step\s*\d)/i.test(l)).length;
  if (numbered >= 2) {
    for (const line of lines) {
      if (line.trim() === "") continue;
      if (/^\s*(?:\d{1,2}[.)]|step\s*\d)/i.test(line) || steps.length === 0) {
        steps.push(line.replace(BULLET, "").trim());
      } else {
        steps[steps.length - 1] = `${steps[steps.length - 1]} ${line.trim()}`;
      }
    }
    return steps.filter((s) => s !== "");
  }
  const joined = lines.join("\n").trim();
  const chunks = /\n\s*\n/.test(joined) ? joined.split(/\n\s*\n/) : joined.split("\n");
  return chunks
    .flatMap((chunk) => {
      const parts = chunk.split("\n").map((l) => l.replace(BULLET, "").trim());
      // A paragraph of whole sentences, one per line, is several steps; a
      // line that continues in lower case is a hard-wrapped one.
      const sentences = parts.length > 1 && parts.every((l) => /^[\p{Lu}\d].*[.!?]$/u.test(l));
      return sentences ? parts : [parts.join(" ").trim()];
    })
    .filter((s) => s !== "");
};

const toIngredients = (lines: ReadonlyArray<string>, unsure: boolean): Array<ExtractedLine> => {
  const out: Array<ExtractedLine> = [];
  let section: string | null = null;
  for (const raw of lines) {
    const line = raw.replace(/^\s*[-•*▢□◦‣–—]\s*/, "").trim();
    if (line === "") continue;
    if (isSectionHeading(line) && parseIngredientLine(line).quantity === null) {
      section = bare(line).replace(/:$/, "").trim() || null;
      continue;
    }
    out.push({ line, section, unsure });
  }
  return out;
};

const toSteps = (lines: ReadonlyArray<string>, unsure: boolean): Array<ExtractedStep> => {
  const out: Array<ExtractedStep> = [];
  let section: string | null = null;
  const groups: Array<{ section: string | null; lines: Array<string> }> = [{ section, lines: [] }];
  for (const line of lines) {
    const text = line.trim();
    if (text !== "" && isSectionHeading(text) && !/[.!?]$/.test(text) && text.length < 40) {
      section = bare(text).replace(/:$/, "").trim() || null;
      groups.push({ section, lines: [] });
      continue;
    }
    groups[groups.length - 1]!.lines.push(line);
  }
  for (const group of groups) {
    for (const text of splitSteps(group.lines)) out.push({ text, section: group.section, unsure });
  }
  return out;
};

// Lines above the recipe that aren't part of it: email headers, page chrome.
const HEADER_LINE = /^(?:from|to|cc|bcc|date|sent)\s*:/i;
const PAGE_JUNK =
  /^(?:skip\s+to|home\b|menu\b|jump\s+to|print\b|advertisement|sponsored|posted\b|share\b|pin\b|save\b|subscribe|sign\s+up|\d+\s+comments?)/i;
// Chat exports start each message with "[12:41, 3/9/2026] Sam:". Chatter
// around the recipe ("ok here is the recipe") is never its title.
const CHAT_PREFIX = /^\[[^\]]{4,40}\]\s*[^:]{1,30}:\s*/;
const CHATTER = /^(?:ok(?:ay)?|hi|hey|hello|here(?:'|’)?s|here\s+is|so|thanks|sure)\b/i;

/** A title is a short first line that isn't metadata or a heading. */
const pickTitle = (intro: ReadonlyArray<string>, meta: Meta) => {
  const lines = intro
    .map((l) =>
      clean(l)
        .replace(CHAT_PREFIX, "")
        .replace(/^subject\s*:\s*/i, ""),
    )
    .filter((l) => l !== "" && !HEADER_LINE.test(l) && !PAGE_JUNK.test(l) && !CHATTER.test(l));
  let title: string | null = null;
  const rest: Array<string> = [];
  for (const line of lines) {
    if (readMeta(line, meta)) continue;
    const text = bare(line);
    if (
      title === null &&
      text.length > 0 &&
      text.length <= 120 &&
      !/[.!?]$/.test(text) &&
      !/^(?:recipe|by\s|from\s|https?:)/i.test(text)
    ) {
      title = text.replace(/^recipe\s*[:：-]\s*/i, "");
      continue;
    }
    rest.push(line);
  }
  return { title, description: rest.length > 0 ? rest.join(" ").slice(0, 2000) : null };
};

/** Reads text that has an ingredients heading. */
const readSections = (lines: ReadonlyArray<string>): TextReading | null => {
  const blocks: Record<Block, Array<string>> = {
    intro: [],
    ingredients: [],
    method: [],
    notes: [],
  };
  const meta: Meta = { servings: null, prepMinutes: null, cookMinutes: null, totalMinutes: null };
  let block: Block = "intro";
  let sawIngredients = false;
  let sawMethod = false;
  for (const raw of lines) {
    const line = clean(raw);
    const heading = headingOf(line);
    if (heading) {
      block = heading;
      sawIngredients ||= heading === "ingredients";
      sawMethod ||= heading === "method";
      continue;
    }
    // "Ingredients: 2 eggs" or "Method: Mix everything."
    const inline = INLINE_HEADING.exec(line);
    const inlineHeading = inline ? headingOf(inline[1]!) : null;
    if (inline && inlineHeading) {
      block = inlineHeading;
      sawIngredients ||= inlineHeading === "ingredients";
      sawMethod ||= inlineHeading === "method";
      blocks[block].push(inline[2]!);
      continue;
    }
    // "Serves 4" and "Prep: 10 min" sit above the method. In the method, "Cook
    // the onions for 10 minutes" is a step.
    if ((block === "intro" || block === "ingredients") && line !== "" && readMeta(line, meta))
      continue;
    blocks[block].push(line);
  }
  if (!sawIngredients) return null;
  let ingredientLines = blocks.ingredients;
  let methodLines = blocks.method;
  if (!sawMethod) {
    // No method heading: the method starts at the first line that reads as a
    // sentence rather than an ingredient.
    const start = ingredientLines.findIndex(
      (l, i) => i > 0 && l.trim() !== "" && !looksLikeIngredient(l) && l.trim().length > 50,
    );
    if (start === -1) return null;
    methodLines = ingredientLines.slice(start);
    ingredientLines = ingredientLines.slice(0, start);
  }
  const { title, description } = pickTitle(blocks.intro, meta);
  const ingredients = toIngredients(ingredientLines, false);
  const steps = toSteps(
    methodLines.filter((l) => !TRAILER.test(l.trim())),
    false,
  );
  if (ingredients.length === 0 || steps.length === 0) return null;
  const notes = blocks.notes.join("\n").trim();
  return {
    clarity: sawMethod && title !== null ? "clear" : "rough",
    recipe: {
      ...emptyExtracted,
      ...meta,
      title,
      description,
      notes: notes === "" ? null : notes,
      ingredients,
      steps,
      unsure: title === null ? ["title"] : [],
    },
  };
};

/**
 * Text with no headings: the first run of ingredient-looking lines is the
 * ingredients, what follows is the method, and what comes before is the title.
 */
const readLoose = (lines: ReadonlyArray<string>): TextReading | null => {
  const cleaned = lines.map(clean);
  const isIngredient = cleaned.map((l) => l !== "" && looksLikeIngredient(l) && l.length <= 160);
  let start = -1;
  let end = -1;
  for (let i = 0; i < cleaned.length; i++) {
    if (!isIngredient[i]) continue;
    let j = i;
    let count = 0;
    while (j < cleaned.length && (isIngredient[j] || cleaned[j] === "")) {
      if (isIngredient[j]) count++;
      j++;
    }
    if (count >= 2) {
      start = i;
      end = j;
      break;
    }
  }
  if (start === -1) return null;
  const meta: Meta = { servings: null, prepMinutes: null, cookMinutes: null, totalMinutes: null };
  const method = cleaned.slice(end).filter((l) => !(l !== "" && readMeta(l, meta)));
  const ingredients = toIngredients(cleaned.slice(start, end), true);
  const steps = toSteps(method, true);
  if (steps.length === 0) return null;
  const { title, description } = pickTitle(cleaned.slice(0, start), meta);
  return {
    clarity: "rough",
    recipe: {
      ...emptyExtracted,
      ...meta,
      title,
      description,
      ingredients,
      steps,
      unsure: ["title", "description"],
    },
  };
};

/** Reads a recipe from plain text, or null when there's no recipe it can find. */
export const readRecipeText = (text: string): TextReading | null => {
  const lines = text
    .replace(/\r\n?/g, "\n")
    .replace(/[   ]/g, " ")
    .split("\n");
  return readSections(lines) ?? readLoose(lines);
};
