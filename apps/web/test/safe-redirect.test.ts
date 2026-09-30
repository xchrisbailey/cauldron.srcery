import { describe, expect, it } from "vite-plus/test";
import { safeRedirect } from "../src/lib/safe-redirect.ts";

describe("safeRedirect", () => {
  it("keeps same-site paths with search and hash", () => {
    expect(safeRedirect("/account")).toBe("/account");
    expect(safeRedirect("/recipes?page=2#top")).toBe("/recipes?page=2#top");
  });

  it("falls back to / when missing or relative", () => {
    expect(safeRedirect(undefined)).toBe("/");
    expect(safeRedirect("")).toBe("/");
    expect(safeRedirect("account")).toBe("/");
  });

  it.each([
    "//evil.example",
    "/\\evil.example",
    "/\\/evil.example",
    "https://evil.example",
    "javascript:alert(1)",
    "/\t/evil.example",
    "/\n/evil.example",
    "/\r/evil.example",
    "/\u0000evil",
    "/ok\u007f",
  ])("rejects %j", (to) => {
    expect(safeRedirect(to)).toBe("/");
  });
});
