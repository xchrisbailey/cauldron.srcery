import { describe, expect, it } from "vite-plus/test";
import { detectTimer, formatTimer } from "../src/timers.ts";

describe("detectTimer", () => {
  const cases: ReadonlyArray<readonly [string, number | null]> = [
    ["Bake 25 minutes", 1500],
    ["simmer for 1 hour", 3600],
    ["Cook 1 1/2 hours", 5400],
    ["Cook 1½ hours", 5400],
    ["Cook 1.5 hrs", 5400],
    ["Roast 1 hr 15 min", 4500],
    ["Roast 1 hour and 15 minutes", 4500],
    ["Bake 10-12 minutes", 720],
    ["Bake 10 to 12 minutes", 720],
    ["Bake 10–12 mins", 720],
    ["Sear 30 seconds", 30],
    ["Sear 30 secs", 30],
    ["Sear 30s", 30],
    ["Boil 45 min.", 2700],
    ["Wait an hour", 3600],
    ["Wait half an hour", 1800],
    ["Wait a minute", 60],
    ["Bake 1 minute 30 seconds", 90],
    ["Bake 25 MINUTES", 1500],
    ["Mix, then bake 20 minutes until golden", 1200],
    ["Stir 2 minutes, then rest 10 minutes", 120],
    ["Simmer 72 hours", 259200],
    ["Simmer 73 hours", null],
    ["Preheat oven to 200C", null],
    ["Add 2 cups flour", null],
    ["serves 4", null],
    ["Rest overnight", null],
    ["Line a 9-inch pan", null],
    ["Add 5 tbsp butter", null],
    ["Use a shallow dish", null],
    ["", null],
  ];
  it.each(cases)("%j -> %j", (text, expected) => {
    expect(detectTimer(text)).toBe(expected);
  });
});

describe("formatTimer", () => {
  const cases: ReadonlyArray<readonly [number, string]> = [
    [45, "45 s"],
    [60, "1 min"],
    [90, "1 min 30 s"],
    [1500, "25 min"],
    [3600, "1 h"],
    [4500, "1 h 15 min"],
    [7200, "2 h"],
  ];
  it.each(cases)("%d -> %s", (seconds, label) => {
    expect(formatTimer(seconds)).toBe(label);
  });
});
