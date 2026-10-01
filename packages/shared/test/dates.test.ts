import { describe, expect, it } from "vite-plus/test";
import { addDays, daysBetween, startOfWeek, weekDays, weekdayOf } from "../src/dates.ts";

describe("addDays", () => {
  const cases: ReadonlyArray<readonly [string, number, string]> = [
    ["2026-10-01", 0, "2026-10-01"],
    ["2026-10-01", 1, "2026-10-02"],
    ["2026-10-01", -1, "2026-09-30"],
    ["2026-01-31", 1, "2026-02-01"],
    ["2026-02-28", 1, "2026-03-01"],
    ["2026-12-31", 1, "2027-01-01"],
    ["2027-01-01", -1, "2026-12-31"],
    ["2028-02-28", 1, "2028-02-29"],
    ["2028-02-29", 1, "2028-03-01"],
    ["2028-03-01", -1, "2028-02-29"],
    ["2028-02-29", 365, "2029-02-28"],
    ["2026-01-01", 365, "2027-01-01"],
    ["2028-01-01", 366, "2029-01-01"],
    ["2026-10-01", 30, "2026-10-31"],
    ["2026-10-01", -400, "2025-08-27"],
  ];
  it.each(cases)("addDays(%s, %i) is %s", (day, n, expected) => {
    expect(addDays(day, n)).toBe(expected);
  });

  it("steps one day at a time over the US spring-forward day", () => {
    expect(addDays("2026-03-07", 1)).toBe("2026-03-08");
    expect(addDays("2026-03-08", 1)).toBe("2026-03-09");
    expect(addDays("2026-03-07", 2)).toBe("2026-03-09");
    expect(addDays("2026-03-09", -2)).toBe("2026-03-07");
  });

  it("steps one day at a time over the EU fall-back day", () => {
    expect(addDays("2026-10-24", 1)).toBe("2026-10-25");
    expect(addDays("2026-10-25", 1)).toBe("2026-10-26");
    expect(addDays("2026-10-26", -2)).toBe("2026-10-24");
  });

  it("round-trips", () => {
    for (const day of ["2026-03-08", "2026-10-25", "2028-02-29", "2026-12-31"]) {
      expect(addDays(addDays(day, 17), -17)).toBe(day);
    }
  });
});

describe("weekdayOf", () => {
  const cases: ReadonlyArray<readonly [string, number]> = [
    ["2026-10-04", 0],
    ["2026-10-05", 1],
    ["2026-10-01", 4],
    ["2026-10-03", 6],
    ["2028-02-29", 2],
    ["2026-03-08", 0],
    ["2026-10-25", 0],
    ["2000-01-01", 6],
  ];
  it.each(cases)("weekdayOf(%s) is %i", (day, expected) => {
    expect(weekdayOf(day)).toBe(expected);
  });
});

describe("startOfWeek", () => {
  it("defaults to Monday", () => {
    expect(startOfWeek("2026-10-01")).toBe("2026-09-28");
  });

  it("returns the day itself when it is already the first day", () => {
    expect(startOfWeek("2026-10-05", 1)).toBe("2026-10-05");
    expect(startOfWeek("2026-10-04", 0)).toBe("2026-10-04");
  });

  it("Monday start: Sunday belongs to the week that began six days earlier", () => {
    expect(startOfWeek("2026-10-04", 1)).toBe("2026-09-28");
    expect(startOfWeek("2026-10-03", 1)).toBe("2026-09-28");
  });

  it("Sunday start: Monday through Saturday follow the Sunday before", () => {
    expect(startOfWeek("2026-10-05", 0)).toBe("2026-10-04");
    expect(startOfWeek("2026-10-10", 0)).toBe("2026-10-04");
    expect(startOfWeek("2026-10-11", 0)).toBe("2026-10-11");
  });

  it("crosses month and year boundaries", () => {
    expect(startOfWeek("2026-03-01", 1)).toBe("2026-02-23");
    expect(startOfWeek("2027-01-01", 1)).toBe("2026-12-28");
    expect(startOfWeek("2027-01-01", 0)).toBe("2026-12-27");
  });

  it("handles the leap day", () => {
    expect(startOfWeek("2028-02-29", 1)).toBe("2028-02-28");
    expect(startOfWeek("2028-02-29", 0)).toBe("2028-02-27");
    expect(startOfWeek("2028-03-05", 1)).toBe("2028-02-28");
  });

  it("handles the DST-change weeks", () => {
    // 2026-03-08 (US) and 2026-10-25 (EU) are both Sundays.
    expect(startOfWeek("2026-03-08", 1)).toBe("2026-03-02");
    expect(startOfWeek("2026-03-08", 0)).toBe("2026-03-08");
    expect(startOfWeek("2026-03-09", 1)).toBe("2026-03-09");
    expect(startOfWeek("2026-10-25", 1)).toBe("2026-10-19");
    expect(startOfWeek("2026-10-25", 0)).toBe("2026-10-25");
    expect(startOfWeek("2026-10-26", 0)).toBe("2026-10-25");
  });

  it("always lands on the requested weekday, at most six days back", () => {
    let day = "2026-02-20";
    for (let i = 0; i < 400; i++) {
      for (const startsOn of [0, 1] as const) {
        const start = startOfWeek(day, startsOn);
        expect(weekdayOf(start)).toBe(startsOn);
        const back = daysBetween(start, day);
        expect(back).toBeGreaterThanOrEqual(0);
        expect(back).toBeLessThanOrEqual(6);
      }
      day = addDays(day, 1);
    }
  });
});

describe("weekDays", () => {
  it("lists seven consecutive days", () => {
    expect(weekDays("2026-09-28")).toEqual([
      "2026-09-28",
      "2026-09-29",
      "2026-09-30",
      "2026-10-01",
      "2026-10-02",
      "2026-10-03",
      "2026-10-04",
    ]);
  });

  it("crosses a year boundary", () => {
    expect(weekDays("2026-12-28")).toEqual([
      "2026-12-28",
      "2026-12-29",
      "2026-12-30",
      "2026-12-31",
      "2027-01-01",
      "2027-01-02",
      "2027-01-03",
    ]);
  });

  it("includes the leap day", () => {
    expect(weekDays("2028-02-28")).toContain("2028-02-29");
    expect(weekDays("2028-02-28")[2]).toBe("2028-03-01");
  });

  it("has no gaps or repeats in the DST-change weeks", () => {
    expect(weekDays("2026-03-02")).toEqual([
      "2026-03-02",
      "2026-03-03",
      "2026-03-04",
      "2026-03-05",
      "2026-03-06",
      "2026-03-07",
      "2026-03-08",
    ]);
    expect(weekDays("2026-10-19")).toEqual([
      "2026-10-19",
      "2026-10-20",
      "2026-10-21",
      "2026-10-22",
      "2026-10-23",
      "2026-10-24",
      "2026-10-25",
    ]);
    expect(weekDays("2026-10-25")[6]).toBe("2026-10-31");
  });
});

describe("daysBetween", () => {
  const cases: ReadonlyArray<readonly [string, string, number]> = [
    ["2026-10-01", "2026-10-01", 0],
    ["2026-10-01", "2026-10-08", 7],
    ["2026-10-08", "2026-10-01", -7],
    ["2026-12-31", "2027-01-01", 1],
    ["2028-02-28", "2028-03-01", 2],
    ["2027-02-28", "2027-03-01", 1],
    ["2026-01-01", "2027-01-01", 365],
    ["2028-01-01", "2029-01-01", 366],
    ["2026-03-07", "2026-03-09", 2],
    ["2026-03-02", "2026-03-09", 7],
    ["2026-10-24", "2026-10-26", 2],
    ["2026-10-19", "2026-10-26", 7],
  ];
  it.each(cases)("daysBetween(%s, %s) is %i", (a, b, expected) => {
    expect(daysBetween(a, b)).toBe(expected);
  });

  it("is the inverse of addDays", () => {
    for (const day of ["2026-03-08", "2026-10-25", "2028-02-29"]) {
      for (const n of [-40, -1, 0, 1, 7, 90]) {
        expect(daysBetween(day, addDays(day, n))).toBe(n);
      }
    }
  });
});
