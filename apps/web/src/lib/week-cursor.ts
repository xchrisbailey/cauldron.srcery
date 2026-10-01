import { isRealDate, startOfWeek, type WeekStartDay } from "@cauldron/shared";
import { useEffect, useState } from "react";
import { usePreference } from "./preference";
import { localToday } from "./recipes";

// Which week Week and Gather show: the `?week=` search, today and the viewer's
// first day of the week, kept in one place so the two pages can't drift.

/** The route search validator: a real `YYYY-MM-DD` day, or nothing. */
export const weekSearch = (search: Record<string, unknown>): { week?: string } =>
  typeof search.week === "string" && isRealDate(search.week) ? { week: search.week } : {};

/**
 * The week to show: the start of the week containing `week` (any day in it),
 * or this week when there is no `week`.
 */
export const resolveWeek = ({
  week,
  today,
  startsOn,
}: {
  week: string | undefined;
  today: string;
  startsOn: WeekStartDay;
}) => ({
  start: startOfWeek(week ?? today, startsOn),
  thisWeek: startOfWeek(today, startsOn),
});

const WEEK_START_KEY = "cauldron:week-start";
const decodeStartsOn = (raw: string | null): WeekStartDay => (raw === "0" ? 0 : 1);

/**
 * Today and the first day of the week are the viewer's own, so they're only
 * known in the browser: null until then. Once known, gives the week to show,
 * the first-day preference, and the search that links to a week (empty for
 * this week, so its URL stays clean).
 */
export function useWeekCursor(week: string | undefined) {
  const [today, setToday] = useState<string | null>(null);
  useEffect(() => setToday(localToday()), []);
  const [startsOn, setStartsOn, loaded] = usePreference<WeekStartDay>(
    WEEK_START_KEY,
    decodeStartsOn,
    1,
  );
  if (today === null || !loaded) return null;
  const { start, thisWeek } = resolveWeek({ week, today, startsOn });
  const searchFor = (weekStart: string): { week?: string } =>
    weekStart === thisWeek ? {} : { week: weekStart };
  return { today, startsOn, setStartsOn, start, thisWeek, searchFor };
}

export type WeekCursor = NonNullable<ReturnType<typeof useWeekCursor>>;
