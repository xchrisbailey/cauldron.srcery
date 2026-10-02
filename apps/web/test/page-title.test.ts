import { copy } from "@cauldron/shared";
import { describe, expect, it } from "vite-plus/test";
import { pageTitle } from "../src/lib/page-title.ts";

describe("pageTitle", () => {
  it("names the page before the app", () => {
    expect(pageTitle(copy.nav.week).meta).toEqual([{ title: "The week · Cauldron" }]);
  });

  it("takes the cook's own text, such as a recipe title", () => {
    expect(pageTitle("Smoke Test Soup").meta).toEqual([{ title: "Smoke Test Soup · Cauldron" }]);
  });

  it("falls back to the app name", () => {
    expect(pageTitle().meta).toEqual([{ title: "Cauldron" }]);
  });
});
