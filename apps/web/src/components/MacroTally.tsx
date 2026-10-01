import * as stylex from "@stylexjs/stylex";
import { copy, hasMacros, type MacroKey, type MacroTally as Tally } from "@cauldron/shared";
import { dayLabel } from "../lib/dates";
import { colors, fonts } from "../styles/tokens.stylex";
import { CloseGlyph } from "./glyphs";
import { IconButton } from "./ui";

// The week's running total of calories and macros, and the chosen day's
// beside it. Protein, carbs and fat use the colors held for the tracker (#23).

const whole = (n: number) => Math.round(n).toLocaleString();

const GRAMS = ["protein", "carbs", "fat"] as const satisfies ReadonlyArray<MacroKey>;

/** Calories from each macro, for the split bar: 4 per gram of protein and carbs, 9 of fat. */
const KCAL_PER_GRAM = { protein: 4, carbs: 4, fat: 9 } as const;

export function MacroTally({
  week,
  daysPlanned,
  day,
  dayTally,
  onClearDay,
}: {
  week: Tally;
  /** Days with at least one counted meal, for the daily average. */
  daysPlanned: number;
  day: string | null;
  dayTally: Tally | null;
  onClearDay: () => void;
}) {
  const any = hasMacros(week);
  const missing = day !== null && dayTally ? dayTally.missing : week.missing;
  return (
    <section aria-label={copy.week.tally.label.text} {...stylex.props(styles.tally)}>
      <div {...stylex.props(styles.groups)}>
        <Group
          label={copy.week.tally.week.text}
          tally={week}
          sub={
            any && daysPlanned > 1
              ? `≈ ${whole(week.totals.calories / daysPlanned)} ${copy.week.tally.macros.calories.text} ${copy.week.tally.perDay.text}`
              : null
          }
        />
        {day !== null && dayTally ? (
          <div {...stylex.props(styles.dayGroup)}>
            <Group label={dayLabel(day, "long")} tally={dayTally} sub={null} today />
            <IconButton label={copy.week.tally.clearDay.text} onClick={onClearDay}>
              <CloseGlyph />
            </IconButton>
          </div>
        ) : null}
      </div>
      {!any ? (
        <p {...stylex.props(styles.note)}>{copy.week.tally.none.text}</p>
      ) : missing > 0 ? (
        <p {...stylex.props(styles.note)}>{copy.week.tally.gaps(missing).text}</p>
      ) : null}
    </section>
  );
}

function Group({
  label,
  tally,
  sub,
  today = false,
}: {
  label: string;
  tally: Tally;
  sub: string | null;
  today?: boolean;
}) {
  const split = GRAMS.map((key) => tally.totals[key] * KCAL_PER_GRAM[key]);
  const splitTotal = split.reduce((a, b) => a + b, 0);
  return (
    <div {...stylex.props(styles.group)}>
      <span {...stylex.props(styles.label, today && styles.labelDay)}>{label}</span>
      <div {...stylex.props(styles.figures)}>
        <span {...stylex.props(styles.kcal)}>
          {whole(tally.totals.calories)}
          <span {...stylex.props(styles.unit)}> {copy.week.tally.macros.calories.text}</span>
        </span>
        {GRAMS.map((key) => (
          <span key={key} {...stylex.props(styles.gram)}>
            <span aria-hidden="true" {...stylex.props(styles.dot, dots[key])} />
            {whole(tally.totals[key])}
            <span {...stylex.props(styles.unit)}>
              {" g "}
              {copy.week.tally.macros[key].text}
            </span>
          </span>
        ))}
      </div>
      {splitTotal > 0 ? (
        <div aria-hidden="true" {...stylex.props(styles.bar)}>
          {GRAMS.map((key, i) => (
            <span
              key={key}
              {...stylex.props(styles.segment, dots[key], styles.share(split[i]! / splitTotal))}
            />
          ))}
        </div>
      ) : null}
      {sub ? <span {...stylex.props(styles.sub)}>{sub}</span> : null}
    </div>
  );
}

const phone = "@media (max-width: 767px)";

const dots = stylex.create({
  protein: { backgroundColor: colors.trackerBlue },
  carbs: { backgroundColor: colors.trackerTeal },
  fat: { backgroundColor: colors.trackerRed },
});

const styles = stylex.create({
  tally: {
    display: "flex",
    flexDirection: "column",
    gap: 10,
    paddingBlock: 14,
    paddingInline: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
  },
  groups: {
    display: "grid",
    gridTemplateColumns: { default: "repeat(auto-fit, minmax(260px, 1fr))", [phone]: "1fr" },
    gap: 16,
  },
  dayGroup: {
    display: "flex",
    alignItems: "flex-start",
    gap: 8,
    paddingInlineStart: { default: 16, [phone]: 0 },
    paddingTop: { default: 0, [phone]: 12 },
    borderInlineStartWidth: { default: 1, [phone]: 0 },
    borderTopWidth: { default: 0, [phone]: 1 },
    borderStyle: "solid",
    borderColor: colors.surface0,
  },
  group: { display: "flex", flexDirection: "column", gap: 6, flexGrow: 1, minWidth: 0 },
  label: {
    fontFamily: fonts.mono,
    fontSize: 10.5,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  labelDay: { color: colors.magic },
  figures: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "baseline",
    columnGap: 16,
    rowGap: 4,
    fontFamily: fonts.mono,
    fontVariantNumeric: "tabular-nums",
  },
  kcal: { fontSize: 22, fontWeight: 600, color: colors.ink, letterSpacing: "-0.02em" },
  gram: {
    display: "inline-flex",
    alignItems: "baseline",
    gap: 6,
    fontSize: 14,
    fontWeight: 500,
    color: colors.ink,
  },
  unit: { fontSize: 12, fontWeight: 400, color: colors.overlay1 },
  dot: { width: 8, height: 8, borderRadius: 999, alignSelf: "center" },
  bar: {
    display: "flex",
    height: 4,
    borderRadius: 4,
    overflow: "hidden",
    backgroundColor: colors.surface0,
  },
  segment: { height: "100%" },
  share: (fraction: number) => ({ width: `${(fraction * 100).toFixed(2)}%` }),
  sub: { fontFamily: fonts.mono, fontSize: 12, color: colors.subtext },
  note: { margin: 0, fontSize: 13, color: colors.subtext },
});
