import * as stylex from "@stylexjs/stylex";
import { addDays, copy } from "@cauldron/shared";
import { weekRangeLabel } from "../lib/dates";
import { colors, fonts } from "../styles/tokens.stylex";
import { Button, IconButton } from "./ui";

/** "‹ Sep 28 – Oct 4 ›" with a way back to this week. Shared by the week and the Gather list. */
export function WeekRange({
  start,
  thisWeek,
  onGo,
}: {
  start: string;
  thisWeek: string;
  onGo: (weekStart: string) => void;
}) {
  return (
    <div {...stylex.props(styles.range)}>
      <IconButton label={copy.week.previousWeek.text} onClick={() => onGo(addDays(start, -7))}>
        ‹
      </IconButton>
      <span aria-live="polite" {...stylex.props(styles.text)}>
        {weekRangeLabel(start)}
      </span>
      <IconButton label={copy.week.nextWeek.text} onClick={() => onGo(addDays(start, 7))}>
        ›
      </IconButton>
      {start !== thisWeek ? (
        <Button variant="ghost" onClick={() => onGo(thisWeek)}>
          {copy.week.thisWeek.text}
        </Button>
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
