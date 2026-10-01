// Calendar days as `YYYY-MM-DD` strings. The arithmetic runs in UTC so it never
// trips over a daylight saving change; the strings themselves mean a day in the
// cook's own calendar.

const toUtc = (day: string) => new Date(`${day}T00:00:00Z`);
const fromUtc = (date: Date) => date.toISOString().slice(0, 10);

/** The day `n` days after `day` (or before, for negative `n`). */
export const addDays = (day: string, n: number): string => {
  const date = toUtc(day);
  date.setUTCDate(date.getUTCDate() + n);
  return fromUtc(date);
};

/** Day of the week, 0 for Sunday to 6 for Saturday. */
export const weekdayOf = (day: string): number => toUtc(day).getUTCDay();

/** Which day a week starts on: 1 for Monday (the default) or 0 for Sunday. */
export type WeekStartDay = 0 | 1;

/** The first day of the week `day` falls in. */
export const startOfWeek = (day: string, startsOn: WeekStartDay = 1): string =>
  addDays(day, -((weekdayOf(day) - startsOn + 7) % 7));

/** The seven days of the week starting on `start`. */
export const weekDays = (start: string): ReadonlyArray<string> =>
  Array.from({ length: 7 }, (_, i) => addDays(start, i));

/** Whole days from `a` to `b` (negative when `b` is earlier). */
export const daysBetween = (a: string, b: string): number =>
  Math.round((toUtc(b).getTime() - toUtc(a).getTime()) / 86_400_000);
