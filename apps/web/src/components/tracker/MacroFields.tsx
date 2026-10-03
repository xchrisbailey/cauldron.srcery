import * as stylex from "@stylexjs/stylex";
import { copy, MACRO_KEYS, type MacroKey, type Macros, type MacrosInput } from "@cauldron/shared";
import { Input } from "../ui";
import { colors, fonts } from "../../styles/tokens.stylex";

// Calories, protein, carbs and fat as four number fields in Geist Mono, kept
// as strings while typing. A blank field is an unknown.

export type MacroDraft = Record<MacroKey, string>;

export const emptyDraft: MacroDraft = { calories: "", protein: "", carbs: "", fat: "" };

const show = (n: number | null) => (n === null ? "" : String(+n.toFixed(1)));

export const draftOf = (macros: Macros): MacroDraft => ({
  calories: macros.calories === null ? "" : String(Math.round(macros.calories)),
  protein: show(macros.protein),
  carbs: show(macros.carbs),
  fat: show(macros.fat),
});

/** The draft as numbers, or null when a field isn't a usable number. */
export const readDraft = (draft: MacroDraft): MacrosInput | null => {
  const out: Record<string, number | null> = {};
  for (const key of MACRO_KEYS) {
    const raw = draft[key].trim();
    if (raw === "") {
      out[key] = null;
      continue;
    }
    const n = Number(raw);
    if (!Number.isFinite(n) || n < 0) return null;
    out[key] = key === "calories" ? Math.round(n) : Math.round(n * 10) / 10;
  }
  return out as MacrosInput;
};

export function MacroFields({
  draft,
  onChange,
  required = false,
}: {
  draft: MacroDraft;
  onChange: (draft: MacroDraft) => void;
  /** Calories must be filled in. */
  required?: boolean;
}) {
  return (
    <div {...stylex.props(styles.grid)}>
      {MACRO_KEYS.map((key) => (
        <div key={key} {...stylex.props(styles.cell)}>
          <span aria-hidden="true" {...stylex.props(styles.label)}>
            {key === "calories" ? null : <span {...stylex.props(styles.dot, dots[key])} />}
            {copy.tracker.macroNames[key].text}
            <span {...stylex.props(styles.unit)}>
              {key === "calories"
                ? copy.tracker.macros.calories.text
                : copy.tracker.macros.grams.text}
            </span>
          </span>
          <Input
            hideLabel
            label={`${copy.tracker.macroNames[key].text} (${key === "calories" ? copy.tracker.macros.calories.text : copy.tracker.macros.grams.text})`}
            inputMode="decimal"
            value={draft[key]}
            required={required && key === "calories"}
            onChange={(e) => onChange({ ...draft, [key]: e.target.value })}
            xstyle={styles.mono}
          />
        </div>
      ))}
    </div>
  );
}

const dots = stylex.create({
  protein: { backgroundColor: colors.trackerBlue },
  carbs: { backgroundColor: colors.trackerTeal },
  fat: { backgroundColor: colors.trackerRed },
});

const styles = stylex.create({
  grid: {
    display: "grid",
    gridTemplateColumns: { default: "repeat(4, 1fr)", "@media (max-width: 480px)": "1fr 1fr" },
    gap: 10,
  },
  cell: { display: "flex", flexDirection: "column", gap: 6 },
  label: {
    display: "inline-flex",
    alignItems: "center",
    gap: 6,
    fontSize: 14,
    fontWeight: 500,
    color: colors.subtext,
  },
  unit: { fontFamily: fonts.mono, fontSize: 12, color: colors.overlay1 },
  dot: { width: 7, height: 7, borderRadius: 999 },
  mono: { fontFamily: fonts.mono, fontVariantNumeric: "tabular-nums" },
});
