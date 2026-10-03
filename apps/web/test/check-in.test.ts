import { addDays, type IntakeDay, type TrackerSettings, type WeighIn } from "@cauldron/shared";
import { describe, expect, it } from "vite-plus/test";
import {
  buildCheckIn,
  hasWeekOfData,
  isCheckInDue,
  trendForEstimate,
} from "../src/lib/check-in.ts";

const today = "2026-10-21";

const none = { calories: false, protein: false, carbs: false, fat: false };
const settings = (checkedInOn: string | null, overridden = none): TrackerSettings => ({
  profile: {
    sex: "male",
    birthDate: "1990-05-01",
    heightCm: 180,
    activity: "moderate",
    goal: "lose",
    weeklyRateKg: 0.5,
    proteinPerKg: 1.8,
    fatShare: 0.25,
    weightUnit: "kg",
    heightUnit: "cm",
  },
  targets: { calories: 2300, protein: 150, carbs: 250, fat: 70, overridden, checkedInOn },
});

const weighInsOver = (days: number): WeighIn[] =>
  [0, days].map((back) => ({ date: addDays(today, -back), weightKg: 80 }));

describe("hasWeekOfData", () => {
  it("needs two weigh-ins at least a week apart", () => {
    expect(hasWeekOfData([])).toBe(false);
    expect(hasWeekOfData([today])).toBe(false);
    expect(hasWeekOfData([today, addDays(today, -6)])).toBe(false);
    expect(hasWeekOfData([today, addDays(today, -7)])).toBe(true);
  });
});

describe("isCheckInDue", () => {
  const due = (s: TrackerSettings, w = weighInsOver(10)) =>
    isCheckInDue({ settings: s, weighIns: w, today });

  it("is due when never checked in and there is a week of data", () => {
    expect(due(settings(null))).toBe(true);
  });

  it("waits a week after the last check-in", () => {
    expect(due(settings(addDays(today, -6)))).toBe(false);
    expect(due(settings(addDays(today, -7)))).toBe(true);
  });

  it("needs a profile, targets and a week of data", () => {
    expect(due({ ...settings(null), profile: null })).toBe(false);
    expect(due({ ...settings(null), targets: null })).toBe(false);
    expect(due(settings(null), weighInsOver(3))).toBe(false);
  });
});

describe("buildCheckIn", () => {
  const weighIns: WeighIn[] = Array.from({ length: 15 }, (_, i) => ({
    date: addDays(today, -14 + i),
    weightKg: 80,
  }));
  const intake: IntakeDay[] = Array.from({ length: 14 }, (_, i) => ({
    date: addDays(today, -14 + i),
    entries: 3,
    totals: { calories: 2200, protein: 150, carbs: 220, fat: 70 },
  }));

  it("is null without a weigh-in", () => {
    expect(
      buildCheckIn({ settings: settings(null), intake, weighIns: [], today, keepOverrides: true }),
    ).toBeNull();
  });

  it("measures from logged days only and proposes targets", () => {
    const result = buildCheckIn({
      settings: settings(null),
      intake,
      weighIns,
      today,
      keepOverrides: true,
    })!;
    expect(result.estimate.loggedDays).toBe(14);
    expect(result.estimate.weighIns).toBe(15);
    // Flat weight on 2200 kcal means about 2200 burned.
    expect(result.estimate.measured).toBeCloseTo(2200, 0);
    expect(result.proposal.targets.calories).toBeLessThan(2200);
  });

  it("keeps hand-set values only when asked", () => {
    const hand = { ...none, protein: true };
    const base = { settings: settings(null, hand), intake, weighIns, today };
    expect(buildCheckIn({ ...base, keepOverrides: true })!.proposal.targets.protein).toBe(150);
    expect(buildCheckIn({ ...base, keepOverrides: false })!.proposal.targets.protein).not.toBe(150);
  });
});

describe("trendForEstimate", () => {
  const losing = (days: number, startKg: number) =>
    Array.from({ length: days }, (_, i) => ({
      date: addDays(today, -(days - 1) + i),
      weightKg: startKg - (0.5 / 7) * i,
    }));

  it("fits a line through a new cook's weigh-ins instead of the lagging trend", () => {
    const trend = trendForEstimate(losing(21, 80), today);
    const change = trend[trend.length - 1]!.trendKg - trend[0]!.trendKg;
    expect(change).toBeCloseTo(-(0.5 / 7) * 20, 5);
  });

  it("uses the smoothed trend once it has warmed up", () => {
    const trend = trendForEstimate(losing(60, 82), today);
    expect(trend.length).toBe(60);
  });
});

describe("isCheckInDue with old weigh-ins", () => {
  it("isn't due when the only weigh-ins are outside the window", () => {
    expect(
      isCheckInDue({
        settings: { profile: {} as never, targets: { checkedInOn: null } },
        weighIns: [{ date: "2026-05-01" }, { date: "2026-05-20" }],
        today: "2026-10-21",
      }),
    ).toBe(false);
  });
});
