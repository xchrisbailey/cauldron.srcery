import * as stylex from "@stylexjs/stylex";
import { type ReactNode, useId } from "react";
import { colors, fonts } from "../styles/tokens.stylex";

// Pick-one controls built on native radio inputs: a row of pills for short
// choices (sex, units, weekly rate) and a vertical list with a line of detail
// for longer ones (activity). The radio is visually hidden but keeps the
// keyboard and screen reader behaviour; the label shows the focus ring.

export interface Choice<T extends string> {
  readonly value: T;
  readonly label: ReactNode;
  readonly hint?: string;
}

interface ChoicesProps<T extends string> {
  readonly legend: string;
  /** Keep the legend for screen readers only, e.g. next to a labelled field. */
  readonly hideLegend?: boolean;
  readonly options: ReadonlyArray<Choice<T>>;
  readonly value: T | null;
  readonly onChange: (value: T) => void;
  readonly error?: string | undefined;
}

export function Pills<T extends string>({
  legend,
  hideLegend = false,
  options,
  value,
  onChange,
  error,
  small = false,
  mono = false,
}: ChoicesProps<T> & { small?: boolean; mono?: boolean }) {
  const name = useId();
  return (
    <fieldset {...stylex.props(styles.fieldset)}>
      <legend {...stylex.props(styles.legend, hideLegend && styles.hidden)}>{legend}</legend>
      <div {...stylex.props(styles.pills)}>
        {options.map((o) => (
          <label
            key={o.value}
            {...stylex.props(
              styles.pill,
              small && styles.pillSmall,
              mono && styles.mono,
              value === o.value && styles.on,
            )}
          >
            <input
              type="radio"
              name={name}
              value={o.value}
              checked={value === o.value}
              onChange={() => onChange(o.value)}
              {...stylex.props(styles.hidden)}
            />
            {o.label}
          </label>
        ))}
      </div>
      {error ? <span {...stylex.props(styles.error)}>{error}</span> : null}
    </fieldset>
  );
}

export function ChoiceList<T extends string>({
  legend,
  options,
  value,
  onChange,
  error,
}: ChoicesProps<T>) {
  const name = useId();
  return (
    <fieldset {...stylex.props(styles.fieldset)}>
      <legend {...stylex.props(styles.legend)}>{legend}</legend>
      <div {...stylex.props(styles.list)}>
        {options.map((o) => (
          <label key={o.value} {...stylex.props(styles.row, value === o.value && styles.on)}>
            <input
              type="radio"
              name={name}
              value={o.value}
              checked={value === o.value}
              onChange={() => onChange(o.value)}
              {...stylex.props(styles.hidden)}
            />
            <span {...stylex.props(styles.rowLabel)}>{o.label}</span>
            {o.hint ? <span {...stylex.props(styles.rowHint)}>{o.hint}</span> : null}
          </label>
        ))}
      </div>
      {error ? <span {...stylex.props(styles.error)}>{error}</span> : null}
    </fieldset>
  );
}

const styles = stylex.create({
  fieldset: { margin: 0, padding: 0, border: "none", minWidth: 0 },
  legend: { padding: 0, marginBottom: 6, fontSize: 14, fontWeight: 500, color: colors.subtext },
  hidden: {
    position: "absolute",
    width: 1,
    height: 1,
    margin: -1,
    padding: 0,
    overflow: "hidden",
    clip: "rect(0 0 0 0)",
    whiteSpace: "nowrap",
    border: 0,
  },
  pills: { display: "flex", flexWrap: "wrap", gap: 8 },
  pill: {
    position: "relative",
    display: "inline-flex",
    alignItems: "center",
    minHeight: 40,
    paddingInline: 14,
    borderRadius: 999,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface1,
    backgroundColor: { default: colors.base, ":hover": colors.surface0 },
    color: colors.ink,
    fontSize: 14,
    fontWeight: 500,
    cursor: "pointer",
    outline: { default: "none", ":focus-within": `2px solid ${colors.magic}` },
    outlineOffset: 2,
  },
  pillSmall: { minHeight: 32, paddingInline: 10, fontSize: 13 },
  mono: { fontFamily: fonts.mono, fontVariantNumeric: "tabular-nums" },
  // A mauve border and mantle fill: mauve fill under ink text fails contrast in Latte.
  on: {
    borderColor: colors.magic,
    backgroundColor: colors.surface0,
    boxShadow: `inset 0 0 0 1px ${colors.magic}`,
  },
  list: { display: "flex", flexDirection: "column", gap: 8 },
  row: {
    display: "flex",
    flexDirection: "column",
    gap: 2,
    paddingBlock: 10,
    paddingInline: 14,
    minHeight: 48,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface1,
    backgroundColor: { default: colors.base, ":hover": colors.surface0 },
    cursor: "pointer",
    outline: { default: "none", ":focus-within": `2px solid ${colors.magic}` },
    outlineOffset: 2,
  },
  rowLabel: { fontSize: 15, fontWeight: 550, color: colors.ink },
  rowHint: { fontSize: 13, color: colors.subtext },
  error: { display: "block", marginTop: 6, fontSize: 13, fontWeight: 500, color: colors.ink },
});
