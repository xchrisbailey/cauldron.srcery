import { addDays } from "@cauldron/shared";

// Labels for calendar days (`YYYY-MM-DD`) in the viewer's locale. Noon local
// time keeps a day from slipping across midnight in any time zone.

const at = (day: string) => new Date(`${day}T12:00:00`);

/** "Wednesday" or "Wed". */
export const weekdayName = (day: string, width: "long" | "short") =>
  at(day).toLocaleDateString(undefined, { weekday: width });

/** The day of the month: "1". */
export const dayOfMonth = (day: string) => String(at(day).getDate());

/** "Wednesday, Oct 1" or "Wed, Oct 1". */
export const dayLabel = (day: string, width: "long" | "short") =>
  at(day).toLocaleDateString(undefined, { weekday: width, month: "short", day: "numeric" });

/** "Sep 28 – Oct 4" for the week starting `start`. */
export const weekRangeLabel = (start: string) => {
  const opts = { month: "short", day: "numeric" } as const;
  return `${at(start).toLocaleDateString(undefined, opts)} – ${at(addDays(start, 6)).toLocaleDateString(undefined, opts)}`;
};
