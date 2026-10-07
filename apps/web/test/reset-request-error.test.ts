import { copy } from "@cauldron/shared";
import { describe, expect, it } from "vite-plus/test";
import { resetRequestErrorMessage } from "../src/lib/reset-request-error.ts";

describe("resetRequestErrorMessage", () => {
  it("maps a 429 status to the rate-limit message", () => {
    expect(resetRequestErrorMessage({ status: 429, statusText: "Too Many Requests" })).toBe(
      copy.errors.tooManyRequests.text,
    );
  });

  it("maps the TOO_MANY_REQUESTS code to the rate-limit message", () => {
    expect(resetRequestErrorMessage({ code: "TOO_MANY_REQUESTS" })).toBe(
      copy.errors.tooManyRequests.text,
    );
  });

  it("uses the generic message for anything else", () => {
    expect(resetRequestErrorMessage({ status: 500 })).toBe(copy.errors.internal.text);
    expect(resetRequestErrorMessage(new Error("network"))).toBe(copy.errors.internal.text);
    expect(resetRequestErrorMessage(undefined)).toBe(copy.errors.internal.text);
  });
});
