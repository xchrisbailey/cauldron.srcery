import { Effect, Result } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { FetchError, isPrivateAddress, RemoteFetch } from "../src/RemoteFetch.ts";

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
    "fc00::1",
    "fd12:3456::1",
    "fe80::1",
    "::ffff:127.0.0.1",
    "::ffff:10.0.0.1",
  ])("refuses %s", (ip) => {
    expect(isPrivateAddress(ip)).toBe(true);
  });

  it.each(["8.8.8.8", "1.1.1.1", "172.32.0.1", "100.128.0.1", "2606:4700::1111", "::ffff:8.8.8.8"])(
    "allows %s",
    (ip) => {
      expect(isPrivateAddress(ip)).toBe(false);
    },
  );
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
