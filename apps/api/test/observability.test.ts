import { describe, expect, it } from "vite-plus/test";
import { parseOtlpHeaders } from "../src/Observability.ts";

describe("parseOtlpHeaders", () => {
  it("reads name=value pairs, trimming and percent-decoding", () => {
    expect(parseOtlpHeaders("authorization=Bearer%20abc, x-team = cauldron")).toEqual({
      authorization: "Bearer abc",
      "x-team": "cauldron",
    });
  });

  it("keeps an equals sign inside a value", () => {
    expect(parseOtlpHeaders("authorization=Basic dXNlcjpwYXNz==")).toEqual({
      authorization: "Basic dXNlcjpwYXNz==",
    });
  });

  it("drops entries with no name or no equals sign", () => {
    expect(parseOtlpHeaders("=nameless,novalue,,ok=1")).toEqual({ ok: "1" });
  });

  it("keeps a value that isn't valid percent-encoding as it is", () => {
    expect(parseOtlpHeaders("x=100%")).toEqual({ x: "100%" });
  });
});
