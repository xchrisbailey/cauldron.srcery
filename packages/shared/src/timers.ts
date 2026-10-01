/**
 * Detect a cooking duration in a method step so the editor can offer a timer
 * chip. Quantities are plain text, not copy-module strings.
 */

const MAX_SECONDS = 60 * 60 * 72;

const VULGAR: Record<string, number> = {
  "½": 0.5,
  "¼": 0.25,
  "¾": 0.75,
  "⅓": 1 / 3,
  "⅔": 2 / 3,
  "⅛": 0.125,
};

const FRACS = "½¼¾⅓⅔⅛";
const AMOUNT = String.raw`(?:\d+\s+\d+\/\d+|\d+\s*[${FRACS}]|\d+(?:\.\d+)?|\d+\/\d+|[${FRACS}]|half\s+an?|an?)`;
const RANGE = String.raw`(${AMOUNT})(?:\s*(?:-|–|—|to)\s*(${AMOUNT}))?`;
const UNIT = String.raw`\s*(hours?|hrs?|h|minutes?|mins?|seconds?|secs?|s)(?![a-z])\.?`;

const FIRST = new RegExp(String.raw`(?<![\w./])${RANGE}${UNIT}`, "gi");
const NEXT = new RegExp(String.raw`(?:\s*(?:,|and)?\s*)${RANGE}${UNIT}`, "iy");

const parseAmount = (raw: string): number | null => {
  const s = raw.trim().toLowerCase();
  if (s === "a" || s === "an") return 1;
  if (s.startsWith("half")) return 0.5;
  let m = /^(\d+)\s+(\d+)\/(\d+)$/.exec(s);
  if (m) return Number(m[1]) + Number(m[2]) / Number(m[3]);
  m = /^(\d+)\s*([½¼¾⅓⅔⅛])$/.exec(s);
  if (m) return Number(m[1]) + VULGAR[m[2]!]!;
  m = /^(\d+)\/(\d+)$/.exec(s);
  if (m) return Number(m[2]) === 0 ? null : Number(m[1]) / Number(m[2]);
  if (s.length === 1 && s in VULGAR) return VULGAR[s]!;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
};

const unitSeconds = (unit: string): number => {
  const u = unit.toLowerCase();
  if (u.startsWith("h")) return 3600;
  if (u.startsWith("m")) return 60;
  return 1;
};

const isWord = (raw: string) => /^(a|an|half)/i.test(raw.trim());

/** Seconds for one `amount[-amount] unit` match; the range's upper bound wins. */
const toSeconds = (lo: string, hi: string | undefined, unit: string): number | null => {
  const raw = hi ?? lo;
  // "a s" / "an h" are not durations; word amounts need a spelled-out unit.
  if (isWord(raw) && unit.length <= 1) return null;
  const amount = parseAmount(raw);
  return amount === null ? null : amount * unitSeconds(unit);
};

/**
 * Seconds for the first cooking duration in `text`, or null. The upper bound of
 * a range is used so the timer covers it. Above 72 hours returns null.
 */
export const detectTimer = (text: string): number | null => {
  try {
    FIRST.lastIndex = 0;
    for (const m of text.matchAll(FIRST)) {
      let total = toSeconds(m[1]!, m[2], m[3]!);
      if (total === null) continue;
      let lastUnit = unitSeconds(m[3]!);
      let end = m.index + m[0].length;
      // "1 hr 15 min", "1 hour and 15 minutes": add smaller trailing units.
      for (;;) {
        NEXT.lastIndex = end;
        const n = NEXT.exec(text);
        if (!n || unitSeconds(n[3]!) >= lastUnit) break;
        const extra = toSeconds(n[1]!, n[2], n[3]!);
        if (extra === null) break;
        total += extra;
        lastUnit = unitSeconds(n[3]!);
        end = NEXT.lastIndex;
      }
      const seconds = Math.round(total);
      if (seconds < 1 || seconds > MAX_SECONDS) return null;
      return seconds;
    }
    return null;
  } catch {
    return null;
  }
};

/** Short plain label: "45 s", "25 min", "1 min 30 s", "1 h", "1 h 15 min". */
export const formatTimer = (seconds: number): string => {
  const total = Math.max(0, Math.round(seconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return m > 0 ? `${h} h ${m} min` : `${h} h`;
  if (m > 0) return s > 0 ? `${m} min ${s} s` : `${m} min`;
  return `${s} s`;
};
