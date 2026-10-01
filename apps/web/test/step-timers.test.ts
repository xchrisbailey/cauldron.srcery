import { describe, expect, it } from "vite-plus/test";
import { clock, secondsLeft } from "../src/lib/step-timers.ts";

describe("clock", () => {
  it("reads minutes and seconds, rounding up", () => {
    expect(clock(0)).toBe("0:00");
    expect(clock(59.2)).toBe("1:00");
    expect(clock(422)).toBe("7:02");
  });

  it("adds hours from an hour", () => {
    expect(clock(3600)).toBe("1:00:00");
    expect(clock(3905)).toBe("1:05:05");
  });
});

describe("secondsLeft", () => {
  it("counts down from the end time while running, never below zero", () => {
    const timer = { total: 60, left: 60, endsAt: 10_000 + 60_000, done: false };
    expect(secondsLeft(timer, 10_000)).toBe(60);
    expect(secondsLeft(timer, 40_000)).toBe(30);
    expect(secondsLeft(timer, 99_000)).toBe(0);
  });

  it("holds the paused amount", () => {
    expect(secondsLeft({ total: 60, left: 12.5, endsAt: null, done: false }, 99_000)).toBe(12.5);
  });
});
