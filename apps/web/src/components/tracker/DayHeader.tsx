import * as stylex from "@stylexjs/stylex";
import { copy, MACRO_KEYS, type MacroKey, type MacroTotals, type Targets } from "@cauldron/shared";
import type { ReactNode } from "react";
import { colors, fonts } from "../../styles/tokens.stylex";
import { ButtonLink } from "../ui";

// Eaten against target for the day: calories large, then protein, carbs and
// fat, each with a bar and what's left (or how far over) in plain numbers.
// Protein, carbs and fat use the colors held for the tracker.

const whole = (n: number) => Math.round(n).toLocaleString();

const unitOf = (key: MacroKey) =>
  key === "calories" ? copy.tracker.macros.calories.text : copy.tracker.macros.grams.text;

export function DayHeader({
  totals,
  targets,
  aside,
}: {
  totals: MacroTotals;
  targets: Targets | null;
  /** Shown beside the calories, such as the day's weigh-in. */
  aside?: ReactNode;
}) {
  return (
    <section aria-label={copy.tracker.header.label.text} {...stylex.props(styles.header)}>
      <div {...stylex.props(styles.top)}>
        <Meter keyName="calories" eaten={totals.calories} target={targets?.calories ?? null} big />
        {aside ? <div {...stylex.props(styles.aside)}>{aside}</div> : null}
      </div>
      <div {...stylex.props(styles.macros)}>
        {MACRO_KEYS.filter((k) => k !== "calories").map((key) => (
          <Meter key={key} keyName={key} eaten={totals[key]} target={targets?.[key] ?? null} />
        ))}
      </div>
      {targets === null ? (
        <div {...stylex.props(styles.noTargets)}>
          <p {...stylex.props(styles.note)}>{copy.tracker.header.noTargets.text}</p>
          <ButtonLink to="/tracker/targets" variant="secondary">
            {copy.tracker.header.setTargets.text}
          </ButtonLink>
        </div>
      ) : null}
    </section>
  );
}

function Meter({
  keyName,
  eaten,
  target,
  big = false,
}: {
  keyName: MacroKey;
  eaten: number;
  target: number | null;
  big?: boolean;
}) {
  const unit = unitOf(keyName);
  const fraction = target === null || target === 0 ? 0 : eaten / target;
  const over = target !== null && eaten > target;
  const remaining = target === null ? null : target - eaten;
  return (
    <div {...stylex.props(styles.meter)}>
      <div {...stylex.props(styles.meterHead)}>
        <span {...stylex.props(styles.label)}>
          {keyName === "calories" ? null : (
            <span aria-hidden="true" {...stylex.props(styles.dot, tints[keyName])} />
          )}
          {copy.tracker.macroNames[keyName].text}
        </span>
        <span {...stylex.props(styles.figures, big && styles.figuresBig)}>
          {whole(eaten)}
          {target === null ? null : (
            <span {...stylex.props(styles.of)}>
              {" / "}
              {whole(target)}
            </span>
          )}
          <span {...stylex.props(styles.unit)}> {unit}</span>
        </span>
      </div>
      {target === null ? null : (
        <>
          <div
            role="meter"
            aria-label={copy.tracker.macroNames[keyName].text}
            aria-valuemin={0}
            aria-valuemax={target}
            aria-valuenow={Math.round(eaten)}
            {...stylex.props(styles.track, big && styles.trackBig)}
          >
            <span
              {...stylex.props(
                styles.fill,
                keyName === "calories" ? styles.fillCalories : tints[keyName],
                styles.width(Math.min(1, fraction)),
              )}
            />
            {over ? (
              <span
                {...stylex.props(styles.overFill, styles.overWidth(Math.min(1, fraction - 1)))}
              />
            ) : null}
          </div>
          <span {...stylex.props(styles.left, over && styles.overText)}>
            {over
              ? copy.tracker.header.over(`${whole(-remaining!)} ${unit}`).text
              : copy.tracker.header.left(`${whole(remaining!)} ${unit}`).text}
          </span>
        </>
      )}
    </div>
  );
}

const phone = "@media (max-width: 767px)";

const tints = stylex.create({
  calories: { backgroundColor: colors.magic },
  protein: { backgroundColor: colors.trackerBlue },
  carbs: { backgroundColor: colors.trackerTeal },
  fat: { backgroundColor: colors.trackerRed },
});

const styles = stylex.create({
  header: {
    display: "flex",
    flexDirection: "column",
    gap: 16,
    paddingBlock: 16,
    paddingInline: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
  },
  top: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "flex-end",
    gap: 16,
  },
  aside: { flexShrink: 0 },
  macros: {
    display: "grid",
    gridTemplateColumns: { default: "repeat(3, 1fr)", [phone]: "1fr" },
    gap: { default: 16, [phone]: 12 },
  },
  meter: { display: "flex", flexDirection: "column", gap: 6, flexGrow: 1, minWidth: 0 },
  meterHead: {
    display: "flex",
    alignItems: "baseline",
    justifyContent: "space-between",
    gap: 8,
  },
  label: {
    display: "inline-flex",
    alignItems: "center",
    gap: 6,
    fontFamily: fonts.mono,
    fontSize: 10.5,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  dot: { width: 8, height: 8, borderRadius: 999 },
  figures: {
    fontFamily: fonts.mono,
    fontVariantNumeric: "tabular-nums",
    fontSize: 14,
    fontWeight: 500,
    color: colors.ink,
    whiteSpace: "nowrap",
  },
  figuresBig: { fontSize: 24, fontWeight: 600, letterSpacing: "-0.02em" },
  of: { color: colors.subtext, fontWeight: 400 },
  unit: { fontSize: 12, fontWeight: 400, color: colors.overlay1 },
  track: {
    position: "relative",
    display: "flex",
    height: 6,
    borderRadius: 6,
    overflow: "hidden",
    backgroundColor: colors.surface0,
  },
  trackBig: { height: 10 },
  fill: { height: "100%", transition: "width 200ms ease" },
  fillCalories: { backgroundColor: colors.magic },
  width: (fraction: number) => ({ width: `${(fraction * 100).toFixed(2)}%` }),
  // How far over, laid across the end of a full bar in the warning color.
  overFill: {
    position: "absolute",
    insetInlineEnd: 0,
    top: 0,
    bottom: 0,
    backgroundColor: colors.heat,
  },
  overWidth: (fraction: number) => ({ width: `${(fraction * 100).toFixed(2)}%` }),
  left: {
    fontFamily: fonts.mono,
    fontSize: 12,
    color: colors.subtext,
    fontVariantNumeric: "tabular-nums",
  },
  overText: { color: colors.ink, fontWeight: 600 },
  noTargets: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopStyle: "solid",
    borderTopColor: colors.surface0,
  },
  note: { margin: 0, fontSize: 14, color: colors.subtext },
});
