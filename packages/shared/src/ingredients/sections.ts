import { isSectionHeading, parseIngredientLine } from "./parse.ts";
import type { ParsedIngredient } from "./schema.ts";

// One rule for ingredient section headings, used by the editor, the text
// importer and the seeds. A heading is either a markdown heading ("## To
// serve"), or a line the parser reads as a group heading ("For the sauce:",
// "FOR THE CRUST", "**Dressing:**") that has no quantity, so "One onion:" stays
// an ingredient.

/** "## To serve", "# Sauce". */
const MARKDOWN = /^\s*#{1,6}\s+(.*)$/;
// Bullets, emphasis and emoji around a heading, and the colon after it.
const LEADING = /^[\s*_>•·▪\-–—=~|▢□◦‣\p{Extended_Pictographic}️‍]+/u;
const TRAILING = /[\s#*_=~|\p{Extended_Pictographic}️‍]+$/u;
const COLON = /[\s:：]+$/;

const bare = (text: string) =>
  text.replace(LEADING, "").replace(TRAILING, "").replace(COLON, "").replace(TRAILING, "").trim();

/** The heading a line names ("For the sauce:" reads as "For the sauce"), or null. */
export function readHeading(line: string): string | null {
  const markdown = MARKDOWN.exec(line);
  if (markdown) return bare(markdown[1]!) || null;
  const text = line.replace(LEADING, "").replace(TRAILING, "");
  if (!isSectionHeading(text) || parseIngredientLine(text).quantity !== null) return null;
  return bare(text) || null;
}

export interface SectionedIngredient extends ParsedIngredient {
  /** The heading above the line, or null before the first one. */
  readonly section: string | null;
}

/**
 * A block of ingredient lines, parsed. Headings become the `section` of the
 * lines under them; blank lines are dropped.
 */
export function readIngredientBlock(lines: ReadonlyArray<string>): Array<SectionedIngredient> {
  const out: Array<SectionedIngredient> = [];
  let section: string | null = null;
  for (const raw of lines) {
    const line = raw.trim();
    if (line === "") continue;
    const heading = readHeading(line);
    if (heading !== null) {
      section = heading;
      continue;
    }
    out.push({ ...parseIngredientLine(line), section });
  }
  return out;
}

export type SectionRow<T> =
  | { readonly kind: "heading"; readonly text: string }
  | { readonly kind: "line"; readonly line: T };

/**
 * The other direction: lines that carry a `section`, with a heading row before
 * each run of lines in a new section.
 */
export function withHeadings<T extends { readonly section: string | null }>(
  lines: ReadonlyArray<T>,
): Array<SectionRow<T>> {
  const out: Array<SectionRow<T>> = [];
  let section: string | null = null;
  for (const line of lines) {
    if (line.section !== section) {
      section = line.section;
      if (section !== null) out.push({ kind: "heading", text: section });
    }
    out.push({ kind: "line", line });
  }
  return out;
}
