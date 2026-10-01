import { describe, expect, it } from "vite-plus/test";
import { resolveWeek, weekSearch } from "../src/lib/week-cursor.ts";

// 2026-09-28 is a Monday, so 09-30 is a Wednesday and 10-01 a Thursday.
describe("resolveWeek", () => {
  it.each([
    {
      name: "a mid-week date resolves to the Monday before it",
      week: "2026-09-30",
      today: "2026-10-01",
      startsOn: 1 as const,
      start: "2026-09-28",
      thisWeek: "2026-09-28",
    },
    {
      name: "a mid-week date resolves to the Sunday before it on a Sunday start",
      week: "2026-09-30",
      today: "2026-10-01",
      startsOn: 0 as const,
      start: "2026-09-27",
      thisWeek: "2026-09-27",
    },
    {
      name: "a Monday is its own week start on a Monday start",
      week: "2026-09-28",
      today: "2026-10-01",
      startsOn: 1 as const,
      start: "2026-09-28",
      thisWeek: "2026-09-28",
    },
    {
      name: "a Sunday belongs to the week before it on a Monday start",
      week: "2026-09-27",
      today: "2026-10-01",
      startsOn: 1 as const,
      start: "2026-09-21",
      thisWeek: "2026-09-28",
    },
    {
      name: "a Sunday is its own week start on a Sunday start",
      week: "2026-09-27",
      today: "2026-10-01",
      startsOn: 0 as const,
      start: "2026-09-27",
      thisWeek: "2026-09-27",
    },
    {
      name: "a missing week is this week",
      week: undefined,
      today: "2026-10-01",
      startsOn: 1 as const,
      start: "2026-09-28",
      thisWeek: "2026-09-28",
    },
    {
      name: "a missing week is this week on a Sunday start",
      week: undefined,
      today: "2026-10-03",
      startsOn: 0 as const,
      start: "2026-09-27",
      thisWeek: "2026-09-27",
    },
  ])("$name", ({ week, today, startsOn, start, thisWeek }) => {
    expect(resolveWeek({ week, today, startsOn })).toEqual({ start, thisWeek });
  });
});

describe("weekSearch", () => {
  it.each([
    { search: { week: "2026-09-30" }, expected: { week: "2026-09-30" } },
    { search: { week: "2026-02-30" }, expected: {} },
    { search: { week: "soon" }, expected: {} },
    { search: { week: 5 }, expected: {} },
    { search: {}, expected: {} },
  ])("$search", ({ search, expected }) => {
    expect(weekSearch(search)).toEqual(expected);
  });
});
