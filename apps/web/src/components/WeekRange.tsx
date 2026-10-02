import * as stylex from "@stylexjs/stylex";
import { addDays, copy } from "@cauldron/shared";
import { weekRangeLabel } from "../lib/dates";
import { colors, fonts } from "../styles/tokens.stylex";
import { ButtonLink, IconButtonLink } from "./ui";

/**
 * "‹ Sep 28 – Oct 4 ›" with a way back to this week. Shared by the week and the Gather list.
 * Each control links to the same page with that week's search; `prefetch` warms a week's
 * data when its link is hovered or focused.
 */
export function WeekRange({
  start,
  thisWeek,
  searchFor,
  prefetch,
}: {
  start: string;
  thisWeek: string;
  searchFor: (weekStart: string) => { week?: string };
  prefetch: (weekStart: string) => void;
}) {
  const previous = addDays(start, -7);
  const next = addDays(start, 7);
  return (
    <div {...stylex.props(styles.range)}>
      <IconButtonLink
        to="."
        search={searchFor(previous)}
        label={copy.week.previousWeek.text}
        onMouseEnter={() => prefetch(previous)}
        onFocus={() => prefetch(previous)}
      >
        ‹
      </IconButtonLink>
      <span aria-live="polite" {...stylex.props(styles.text)}>
        {weekRangeLabel(start)}
      </span>
      <IconButtonLink
        to="."
        search={searchFor(next)}
        label={copy.week.nextWeek.text}
        onMouseEnter={() => prefetch(next)}
        onFocus={() => prefetch(next)}
      >
        ›
      </IconButtonLink>
      {start !== thisWeek ? (
        <ButtonLink
          to="."
          search={searchFor(thisWeek)}
          variant="ghost"
          onMouseEnter={() => prefetch(thisWeek)}
          onFocus={() => prefetch(thisWeek)}
        >
          {copy.week.thisWeek.text}
        </ButtonLink>
      ) : null}
    </div>
  );
}

const styles = stylex.create({
  range: { display: "flex", alignItems: "center", gap: 4, marginTop: -6 },
  text: {
    minWidth: 130,
    textAlign: "center",
    fontFamily: fonts.mono,
    fontSize: 13,
    color: colors.subtext,
  },
});
