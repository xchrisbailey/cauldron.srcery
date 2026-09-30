/**
 * Ingredient line parser. Plain, synchronous, deterministic, never throws.
 *
 * "1 1/2 cups (190g) flour, sifted" becomes
 *   quantity { min: 1.5, max: null }, unit "cup", item "flour",
 *   note "sifted", alt { quantity 190, unit "g" }.
 *
 * Design choices:
 * - Sizes ("large", "medium", "small") are not units. They stay in the item:
 *   "2 large eggs" is item "large eggs", so nothing the author wrote is lost.
 * - "plus": "1 cup plus 2 tablespoons milk" keeps the first measure and puts the
 *   rest in the note ("plus 2 tablespoons"). It is not summed.
 * - `alt` is a parenthetical measure: either the same amount in another unit
 *   ("1 1/2 cups (190g) flour") or the per-container size ("1 (14 oz) can
 *   tomatoes" is quantity 1, unit can, alt 14 oz). Other parentheticals become
 *   part of the note.
 * - Thousands separators are read: "1,000 g flour" is 1000 g.
 * - "400g/14oz tin tomatoes" (and "1 cup / 240 ml milk"): a slash after the unit
 *   gives the alternate measure. "tin" is not a unit, so it stays in the item:
 *   quantity 400 g, alt 14 oz, item "tin tomatoes". "can" is a unit, so
 *   "400g/14oz can tomatoes" keeps the amount and alt the same way with item "can tomatoes".
 * - "2 x 400g cans chickpeas" is quantity 2, unit can, alt 400 g, item "chickpeas".
 * - Preparation-style measure modifiers before a unit ("heaping", "heaped",
 *   "level", "scant", "rounded") go to the note: "1 heaping tsp salt" is 1 tsp,
 *   note "heaping".
 * - An article after a quantity is dropped: "1/2 an onion", "half a lemon"
 *   are 0.5 of "onion" and "lemon". "half" is 0.5.
 * - "dozen" is a multiplier, not a unit: "2 dozen eggs" is 24 "eggs" and
 *   "half a dozen eggs" is 6.
 * - "each" right after a unit moves to the note: "2 tbsp each salt and
 *   pepper" is 2 tbsp of "salt and pepper", note "each".
 * - "12 oz. package spaghetti": a weight followed by a container word is the
 *   weight as the measure with the container left in the item: 12 oz,
 *   item "package spaghetti". (Only a measure before a container, as in
 *   "1 (14 oz) can" or "1 14-ounce can", makes the container the unit.)
 * - Bare "oz" is weight; only "fl oz" or "fluid ounce" is volume. "T" is tbsp
 *   and "t" is tsp.
 * - Lines with no leading quantity ("Juice of 1 lemon", "Salt, to taste") have
 *   quantity and unit null. Units are only recognized after a quantity.
 * - `note` is tidied text: the part after the first top-level comma, loose
 *   trailing phrases ("to taste", "for serving", "divided"), and parentheticals
 *   that are not measures, joined with ", ".
 */
import type { ParsedIngredient, Quantity, AltMeasure } from "./schema.ts";
import { lookupUnit, UNITS } from "./units.ts";

const VULGAR: Readonly<Record<string, string>> = {
  "½": "1/2",
  "⅓": "1/3",
  "⅔": "2/3",
  "¼": "1/4",
  "¾": "3/4",
  "⅕": "1/5",
  "⅖": "2/5",
  "⅗": "3/5",
  "⅘": "4/5",
  "⅙": "1/6",
  "⅚": "5/6",
  "⅛": "1/8",
  "⅜": "3/8",
  "⅝": "5/8",
  "⅞": "7/8",
};

const NUMBER_WORDS: Readonly<Record<string, number>> = {
  a: 1,
  an: 1,
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
  eleven: 11,
  twelve: 12,
  half: 0.5,
};

/** "a few", "a couple of" are not quantities. */
const VAGUE_AFTER_A = new Set(["few", "couple", "little", "lot", "bit", "handful", "splash"]);

const TRAILING_PHRASES =
  /\s+(to taste|for serving|for garnish|for garnishing|for dusting|for frying|for greasing|as needed|divided)$/i;

function normalize(line: string): string {
  return line
    .replace(new RegExp(`(?:(\\d+)\\s*)?([${Object.keys(VULGAR).join("")}])`, "g"), (_m, d, f) =>
      d ? `${d} ${VULGAR[f]}` : ` ${VULGAR[f]} `,
    )
    .replace(/[‐-―−]/g, "-")
    .replace(/[\s ]+/g, " ")
    .trim();
}

function stripBullet(text: string): string {
  return text.replace(/^(?:[-*•·▪◦‣]+\s+|[•·▪◦‣]+)/, "").trim();
}

interface Parsed<T> {
  readonly value: T;
  readonly rest: string;
}

function parseSingleNumber(s: string): Parsed<number> | null {
  // Thousands separators: "1,000", "12,500.5". Must come before the plain number.
  let m = /^(\d{1,3}(?:,\d{3})+(?:\.\d+)?)(?!\d)/.exec(s);
  if (m) return { value: Number(m[1]!.replace(/,/g, "")), rest: s.slice(m[0].length) };
  m = /^(\d+)(?:\s+|-)(\d+)\/(\d+)/.exec(s);
  if (m && Number(m[3]) !== 0) {
    return { value: Number(m[1]) + Number(m[2]) / Number(m[3]), rest: s.slice(m[0].length) };
  }
  m = /^(\d+)\/(\d+)/.exec(s);
  if (m && Number(m[2]) !== 0) {
    return { value: Number(m[1]) / Number(m[2]), rest: s.slice(m[0].length) };
  }
  m = /^(\d+\.\d+|\.\d+|\d+)/.exec(s);
  if (m) return { value: Number(m[1]), rest: s.slice(m[0].length) };
  m = /^([A-Za-z]+)(?=\s|$)/.exec(s);
  if (m) {
    const word = m[1]!.toLowerCase();
    const value = NUMBER_WORDS[word];
    if (value !== undefined) {
      const next = /^\s*([A-Za-z]+)/.exec(s.slice(m[0].length));
      // "half and half" is an ingredient, not a quantity.
      if (word === "half" && next && next[1]!.toLowerCase() === "and") return null;
      if ((word === "a" || word === "an") && (!next || VAGUE_AFTER_A.has(next[1]!.toLowerCase()))) {
        return null;
      }
      return { value, rest: s.slice(m[0].length) };
    }
  }
  return null;
}

/** A number or a range ("2-3", "2 to 3") at the start of `s`. */
function parseQuantity(s: string): Parsed<Quantity> | null {
  const first = parseSingleNumber(s);
  if (!first) return null;
  const sep = /^\s*(?:-\s*|\s+to\s+)/.exec(first.rest);
  if (sep) {
    const second = parseSingleNumber(first.rest.slice(sep[0].length));
    if (second && second.value >= first.value) {
      return { value: { min: first.value, max: second.value }, rest: second.rest };
    }
  }
  return { value: { min: first.value, max: null }, rest: first.rest };
}

/** A unit word or two at the start of `s`. */
function parseUnit(s: string): Parsed<AltMeasure["unit"]> | null {
  const two = /^([A-Za-z]+)\.?\s+([A-Za-z]+)\.?(?=\s|$)/.exec(s);
  if (two) {
    const code = lookupUnit(`${two[1]} ${two[2]}`);
    if (code && UNITS[code].abbr === "fl oz") return { value: code, rest: s.slice(two[0].length) };
  }
  // A unit ends at a space, "(", "/" (alternate measure) or a dot glued to the
  // next word ("1 tsp.salt").
  const one = /^([A-Za-z]+)(?:\.(?=[A-Za-z])|\.?(?=\s|$|\(|\/))/.exec(s);
  if (one) {
    const code = lookupUnit(one[1]!);
    if (code) return { value: code, rest: s.slice(one[0].length) };
  }
  return null;
}

/** "(190g)", "(28-ounce)", "(about 8 cups)": a whole parenthetical that is one measure. */
function parseMeasure(text: string): AltMeasure | null {
  const cleaned = text
    .trim()
    .replace(/^(?:about|approx\.?|approximately|roughly|around|~)\s*/i, "")
    .replace(/^(\d[\d./ ]*?)-(?=[A-Za-z])/, "$1 ")
    .replace(/\s+each$/i, "");
  const q = parseQuantity(cleaned);
  if (!q) return null;
  const u = parseUnit(q.rest.trim());
  if (!u || u.rest.trim() !== "") return null;
  return { quantity: q.value, unit: u.value };
}

function splitAtComma(text: string): readonly [string, string | null] {
  let depth = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text[i]!;
    if (c === "(") depth++;
    else if (c === ")") depth = Math.max(0, depth - 1);
    else if (
      c === "," &&
      depth === 0 &&
      !/^\s*\d/.test(text.slice(i + 1)) &&
      !/\d/.test(text[i - 1] ?? "")
    ) {
      return [text.slice(0, i).trim(), text.slice(i + 1).trim()];
    }
  }
  return [text, null];
}

const tidy = (s: string) => s.replace(/\s+/g, " ").trim();

function cleanNote(note: string): string {
  return tidy(note.replace(/\(?\boptional\b\)?/gi, " ")).replace(/^[,;:\s-]+|[,;:\s-]+$/g, "");
}

export function parseIngredientLine(line: string): ParsedIngredient {
  try {
    return parse(line);
  } catch {
    return blank(line, line.trim());
  }
}

const scale12 = (q: Quantity): Quantity => ({
  min: q.min * 12,
  max: q.max === null ? null : q.max * 12,
});

function blank(original: string, item: string): ParsedIngredient {
  return { quantity: null, unit: null, item, note: null, optional: false, alt: null, original };
}

function parse(original: string): ParsedIngredient {
  const text = stripBullet(normalize(original));
  if (text === "") return blank(original, "");

  const [headRaw, commaNote] = splitAtComma(text);
  const notes: string[] = [];
  let optional = false;
  let alt: AltMeasure | null = null;

  // Parentheticals in the head: optional flag, first measure as alt, the rest as notes.
  const parenNotes: string[] = [];
  let head = headRaw.replace(/\(([^()]*)\)/g, (_m, inner: string) => {
    if (/^\s*optional\s*$/i.test(inner)) {
      optional = true;
    } else {
      const measure = alt === null ? parseMeasure(inner) : null;
      if (measure) alt = measure;
      else if (tidy(inner) !== "") parenNotes.push(tidy(inner));
    }
    return " ";
  });
  head = tidy(head);
  if (/\boptional\b/i.test(head)) {
    optional = true;
    head = tidy(head.replace(/\boptional\b/gi, " "));
  }

  const trailing = TRAILING_PHRASES.exec(head);
  if (trailing) head = head.slice(0, trailing.index).trim();

  // Leading quantity, unit, and optional "plus <measure>".
  let quantity: Quantity | null = null;
  let unit: AltMeasure["unit"] | null = null;
  let unitText = "";
  let plusNote: string | null = null;
  let item = head;

  const q = parseQuantity(head);
  if (q && (q.rest === "" || /^(?:\s|[A-Za-z(])/.test(q.rest) || /^-[A-Za-z]/.test(q.rest))) {
    let rest = q.rest.trim();
    const hyphenWord = /^-([A-Za-z]+)/.exec(rest);
    if (hyphenWord && lookupUnit(hyphenWord[1]!) === null) {
      rest = "";
      item = head; // "5-minute sauce": not a quantity
    } else {
      if (hyphenWord) rest = rest.slice(1);
      quantity = q.value;

      // "2 x 400g cans chickpeas": a count of packs, each with a size.
      const times = /^[x×]\s*(?=\d)/i.exec(rest);
      if (times) rest = rest.slice(times[0].length);

      // "1/2 an onion", "half a lemon": the article adds nothing after a quantity.
      const article = /^an?\s+(?=\S)/i.exec(rest);
      if (article) rest = rest.slice(article[0].length);

      // "2 dozen eggs": a multiplier.
      const dozen = /^dozen\b\s*/i.exec(rest);
      if (dozen) {
        quantity = scale12(quantity);
        rest = rest.slice(dozen[0].length);
      }

      // "1 14-ounce can tomatoes": size measure before a container unit.
      const size = /^(\d+(?:\.\d+)?)[\s-]*([A-Za-z]+)\.?\s+([A-Za-z]+)(.*)$/.exec(rest);
      if (size && alt === null) {
        const sizeUnit = lookupUnit(size[2]!);
        const container = lookupUnit(size[3]!);
        if (
          sizeUnit &&
          UNITS[sizeUnit].dimension !== "count" &&
          container &&
          UNITS[container].dimension === "count"
        ) {
          alt = { quantity: { min: Number(size[1]), max: null }, unit: sizeUnit };
          rest = `${size[3]}${size[4]}`;
        }
      }

      // "1 heaping tsp salt": how the measure is filled belongs in the note.
      let measureNote: string | null = null;
      const modifier = /^(heaping|heaped|level|scant|rounded)\s+(?=[A-Za-z])/i.exec(rest);
      if (modifier && parseUnit(rest.slice(modifier[0].length))) {
        measureNote = modifier[1]!.toLowerCase();
        rest = rest.slice(modifier[0].length);
      }

      const u = parseUnit(rest);
      if (u) {
        unit = u.value;
        unitText = rest.slice(0, rest.length - u.rest.length).trim();
        rest = u.rest.trim();
        if (measureNote) notes.push(measureNote);
        // "400g/14oz tin tomatoes", "1 cup / 240 ml milk": alternate measure after a slash.
        const slash = /^\/\s*/.exec(rest);
        if (slash) {
          const altQ = parseQuantity(rest.slice(slash[0].length));
          const altU = altQ ? parseUnit(altQ.rest.trim()) : null;
          if (altQ && altU) {
            if (alt === null) alt = { quantity: altQ.value, unit: altU.value };
            rest = altU.rest.trim();
          }
        }
        // "2 tbsp each salt and pepper": "each" is a note.
        const each = /^each\b\s*/i.exec(rest);
        if (each) {
          notes.push("each");
          rest = rest.slice(each[0].length);
        }
        const plus = /^(?:plus|\+)\s+/i.exec(rest);
        if (plus) {
          const extra = parseQuantity(rest.slice(plus[0].length));
          if (extra) {
            const eu = parseUnit(extra.rest.trim());
            const after = eu ? eu.rest : extra.rest;
            const consumed = rest.slice(0, rest.length - after.length).trim();
            plusNote = consumed;
            rest = after.trim();
          }
        }
        rest = rest.replace(/^of\s+/i, "");
      }
      item = rest;
    }
  }

  if (item === "") {
    // "2 cups" / "3 cloves": nothing else to call the item, so the unit word is it.
    if (unit !== null) {
      item = unitText;
      unit = null;
      quantity = null;
      alt = null;
    } else {
      item = tidy(head) || text;
      quantity = null;
    }
  }

  if (plusNote) notes.push(plusNote);
  notes.push(...parenNotes);
  if (trailing) notes.push(trailing[1]!.toLowerCase());
  if (commaNote !== null) {
    if (/\boptional\b/i.test(commaNote)) optional = true;
    const cleaned = cleanNote(commaNote);
    if (cleaned !== "") notes.push(cleaned);
  }

  return {
    quantity,
    unit,
    item,
    note: notes.length > 0 ? notes.join(", ") : null,
    optional,
    alt,
    original,
  };
}

/**
 * Whether a line is a group heading rather than an ingredient: "For the sauce:",
 * or "FOR THE CRUST". Callers use it to start a new section.
 */
export function isSectionHeading(line: string): boolean {
  const text = stripBullet(normalize(line)).replace(/:$/, "").trim();
  if (text === "" || text.length > 60) return false;
  if (/\d/.test(text) || /[,()]/.test(text)) return false;
  if (normalize(line).trim().endsWith(":")) return true;
  return /^for (the )?\w+/i.test(text) && text.split(" ").length <= 5;
}
