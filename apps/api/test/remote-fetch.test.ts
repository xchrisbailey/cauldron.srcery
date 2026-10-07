import { Effect, Result } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { checkRemoteUrl, FetchError, isPrivateAddress, RemoteFetch } from "../src/RemoteFetch.ts";

describe("isPrivateAddress", () => {
  it.each([
    "10.0.0.1",
    "10.255.255.255",
    "127.0.0.1",
    "127.1.2.3",
    "169.254.169.254",
    "172.16.0.1",
    "172.31.255.255",
    "192.168.1.1",
    "100.64.0.1",
    "100.127.255.255",
    "::1",
    // IPv6 forms that carry a private IPv4, as the URL parser writes them.
    "::ffff:7f00:1",
    "::7f00:1",
    "::ffff:a9fe:a9fe",
    "::ffff:0:7f00:1",
    "64:ff9b::7f00:1",
    "2002:7f00:1::",
    "2001::1",
    "2001:db8::1",
    "100::1",
    "fec0::1",
    "192.88.99.1",
    "fc00::1",
    "fd12:3456::1",
    "fe80::1",
    "::ffff:127.0.0.1",
    "::ffff:10.0.0.1",
  ])("refuses %s", (ip) => {
    expect(isPrivateAddress(ip)).toBe(true);
  });

  it.each([
    "8.8.8.8",
    "1.1.1.1",
    "172.32.0.1",
    "100.128.0.1",
    "2606:4700::1111",
    "::ffff:8.8.8.8",
    "2001:4860:4860::8888",
  ])("allows %s", (ip) => {
    expect(isPrivateAddress(ip)).toBe(false);
  });
});

describe("RemoteFetch.layer", () => {
  const attempt = (url: string) =>
    Effect.gen(function* () {
      const remote = yield* RemoteFetch;
      return yield* remote.get(url, { maxBytes: 1024 }).pipe(Effect.result);
    }).pipe(Effect.provide(RemoteFetch.layer), Effect.runPromise);

  it.each([
    "ftp://x",
    "http://user:pw@example.com",
    "http://127.0.0.1/",
    "http://localhost/",
    "http://[::1]/",
    "http://example.com:8080/",
  ])("blocks %s without touching the network", async (url) => {
    const result = await attempt(url);
    expect(Result.isFailure(result)).toBe(true);
    if (Result.isFailure(result)) {
      expect(result.failure).toBeInstanceOf(FetchError);
      expect(result.failure.reason).toBe("blocked");
    }
  });
});

describe("DNS check", () => {
  const check = (answer: () => Promise<ReadonlyArray<string>>) =>
    checkRemoteUrl("https://recipes.example.com/pie", answer).pipe(
      Effect.result,
      Effect.runPromise,
    );

  it("blocks a name that resolves to a public and a private address", async () => {
    const result = await check(async () => ["93.184.216.34", "10.0.0.5"]);
    expect(Result.isFailure(result) && result.failure).toMatchObject({
      reason: "blocked",
      detail: "private address",
    });
  });

  it("passes a name that resolves only to public addresses", async () => {
    const result = await check(async () => ["93.184.216.34", "2606:4700::1111"]);
    expect(Result.isSuccess(result)).toBe(true);
  });

  it("blocks an empty answer", async () => {
    const result = await check(async () => []);
    expect(Result.isFailure(result) && result.failure).toMatchObject({
      reason: "blocked",
      detail: "private address",
    });
  });

  it("reports a failing lookup as unreachable", async () => {
    const result = await check(async () => {
      throw new Error("ENOTFOUND");
    });
    expect(Result.isFailure(result) && result.failure).toMatchObject({ reason: "unreachable" });
  });
});
