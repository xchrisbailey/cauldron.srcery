import {
  ConflictError,
  ForbiddenError,
  InvalidRequestError,
  NotFoundError,
  TooManyRequestsError,
  UnauthorizedError,
  UnavailableError,
} from "@cauldron/api-spec";
import { Schema } from "effect";
import { HttpClientError, HttpClientRequest } from "effect/http";
import { describe, expect, it } from "vite-plus/test";
import { failureOf, messageOr, refused, retryWhile } from "../src/lib/api-failure.ts";

// Real error instances: the typed client decodes each wire body with these
// schemas, so decoding one here gives exactly what callApi rejects with.
const body = (code: string, message: string) => ({ error: { code, message } });
const notFound = Schema.decodeUnknownSync(NotFoundError)(body("not_found", "No such recipe"));
const invalid = Schema.decodeUnknownSync(InvalidRequestError)(
  body("invalid_request", "That meal is full"),
);
const conflict = Schema.decodeUnknownSync(ConflictError)(body("conflict", "Saved already"));
const unavailable = Schema.decodeUnknownSync(UnavailableError)(body("unavailable", "Not now"));
const unauthorized = Schema.decodeUnknownSync(UnauthorizedError)(body("unauthorized", "Sign in"));
const forbidden = Schema.decodeUnknownSync(ForbiddenError)(body("forbidden", "Not yours"));
const tooMany = Schema.decodeUnknownSync(TooManyRequestsError)({
  error: { code: "too_many_requests", message: "Slow down", retryAfterSeconds: 30 },
});

describe("failureOf", () => {
  it("reads the tag and message of each API error", () => {
    expect(failureOf(notFound)).toEqual({ tag: "NotFound", message: "No such recipe" });
    expect(failureOf(invalid).tag).toBe("InvalidRequest");
    expect(failureOf(conflict).tag).toBe("Conflict");
    expect(failureOf(tooMany)).toEqual({ tag: "TooManyRequests", message: "Slow down" });
    expect(failureOf(unavailable).tag).toBe("Unavailable");
    expect(failureOf(unauthorized).tag).toBe("Unauthorized");
    expect(failureOf(forbidden).tag).toBe("Forbidden");
  });

  it("calls the client's transport error a network failure", () => {
    const request = HttpClientRequest.get("/v1/plan");
    const offline = new HttpClientError.HttpClientError({
      reason: new HttpClientError.TransportError({
        request,
        cause: new TypeError("Failed to fetch"),
      }),
    });
    expect(failureOf(offline).tag).toBe("Network");
    const unreadable = new HttpClientError.HttpClientError({
      reason: new HttpClientError.EncodeError({ request }),
    });
    expect(failureOf(unreadable).tag).toBe("Defect");
  });

  it("calls a fetch TypeError a network failure", () => {
    expect(failureOf(new TypeError("Failed to fetch"))).toEqual({
      tag: "Network",
      message: "Failed to fetch",
    });
  });

  it("calls anything else a defect", () => {
    expect(failureOf(new Error("boom"))).toEqual({ tag: "Defect", message: "boom" });
    expect(failureOf("nope")).toEqual({ tag: "Defect", message: "" });
    expect(failureOf(undefined).tag).toBe("Defect");
  });
});

describe("refused and retryWhile", () => {
  it("refuses NotFound, InvalidRequest, Unauthorized and Forbidden only", () => {
    expect(refused(notFound)).toBe(true);
    expect(refused(invalid)).toBe(true);
    expect(refused(unauthorized)).toBe(true);
    expect(refused(forbidden)).toBe(true);
    expect(refused(unavailable)).toBe(false);
    expect(refused(tooMany)).toBe(false);
    expect(refused(new TypeError("Failed to fetch"))).toBe(false);
    expect(refused(new Error("boom"))).toBe(false);
  });

  it("retries up to the maximum, and never after a refusal", () => {
    const retry = retryWhile(2);
    const offline = new TypeError("Failed to fetch");
    expect(retry(0, offline)).toBe(true);
    expect(retry(1, offline)).toBe(true);
    expect(retry(2, offline)).toBe(false);
    expect(retry(0, notFound)).toBe(false);
    expect(retryWhile(5)(4, new Error("boom"))).toBe(true);
  });
});

describe("messageOr", () => {
  it("shows the API's plain message when it sent one", () => {
    expect(messageOr(invalid, "Couldn't save")).toBe("That meal is full");
    expect(messageOr(tooMany, "Couldn't start")).toBe("Slow down");
    expect(messageOr(unavailable, "Couldn't")).toBe("Not now");
  });

  it("falls back for everything else", () => {
    expect(messageOr(notFound, "Couldn't save")).toBe("Couldn't save");
    expect(messageOr(new TypeError("Failed to fetch"), "Couldn't save")).toBe("Couldn't save");
    expect(messageOr(new Error("boom"), "Couldn't save")).toBe("Couldn't save");
  });
});
