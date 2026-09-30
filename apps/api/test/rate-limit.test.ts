import { Authorization, CurrentUser, RateLimit, RateLimitPolicy } from "@cauldron/api-spec";
import { User, UserId } from "@cauldron/shared";
import { Effect, Layer, Schema } from "effect";
import { HttpRouter, HttpServer, HttpServerRequest } from "effect/http";
import { HttpApi, HttpApiBuilder, HttpApiEndpoint, HttpApiGroup } from "effect/http-api";
import { afterAll, describe, expect, it } from "vite-plus/test";
import { AppConfig } from "../src/AppConfig.ts";
import { RateLimitLive } from "../src/http/RateLimit.ts";

class TestApi extends HttpApi.make("test").add(
  HttpApiGroup.make("things").add(
    HttpApiEndpoint.get("limited", "/limited", { success: Schema.String })
      .middleware(RateLimit)
      .annotate(RateLimitPolicy, { limit: 2, window: "1 minute" }),
    HttpApiEndpoint.get("open", "/open", { success: Schema.String }),
  ),
) {}

const Handlers = HttpApiBuilder.group(TestApi, "things", (handlers) =>
  Effect.succeed(
    handlers
      .handle("limited", () => Effect.succeed("ok"))
      .handle("open", () => Effect.succeed("ok")),
  ),
);

const makeHandler = (trustProxy: boolean) =>
  HttpRouter.toWebHandler(
    HttpApiBuilder.layer(TestApi).pipe(
      Layer.provide(Handlers),
      Layer.provide(RateLimitLive),
      Layer.provide(AppConfig.layerTest({ trustProxy })),
      Layer.provide(HttpServer.layerServices),
    ),
    { disableLogger: true },
  );

const untrusted = makeHandler(false);
const trusted = makeHandler(true);
afterAll(() => Promise.all([untrusted.dispose(), trusted.dispose()]));

const get = (path: string, headers: Record<string, string> = {}, server = trusted) =>
  server.handler(new Request(`http://localhost${path}`, { headers }));

const as = (ip: string) => ({ "x-client-ip": ip });

describe("RateLimit middleware", () => {
  it("allows the policy's limit, then answers 429 with the error body and Retry-After", async () => {
    expect((await get("/limited", as("1.1.1.1"))).status).toBe(200);
    expect((await get("/limited", as("1.1.1.1"))).status).toBe(200);
    const res = await get("/limited", as("1.1.1.1"));
    expect(res.status).toBe(429);
    const body = (await res.json()) as any;
    expect(body.error.code).toBe("too_many_requests");
    expect(body.error.message).toEqual(expect.any(String));
    expect(body.error.retryAfterSeconds).toBeGreaterThanOrEqual(1);
    expect(body.error.retryAfterSeconds).toBeLessThanOrEqual(60);
    expect(res.headers.get("retry-after")).toBe(String(body.error.retryAfterSeconds));
  });

  it("keeps a separate budget per client IP when the proxy is trusted", async () => {
    for (let i = 0; i < 3; i++) await get("/limited", as("2.2.2.2"));
    expect((await get("/limited", as("2.2.2.2"))).status).toBe(429);
    expect((await get("/limited", as("3.3.3.3"))).status).toBe(200);
  });

  it("ignores spoofed x-forwarded-for and x-client-ip when TRUST_PROXY is false", async () => {
    // No socket in a web handler, so every request shares the "unknown" address.
    let last = 0;
    for (let i = 0; i < 3; i++) {
      const res = await get(
        "/limited",
        { "x-forwarded-for": `9.9.9.${i}`, "x-client-ip": `8.8.8.${i}` },
        untrusted,
      );
      last = res.status;
    }
    expect(last).toBe(429);
  });

  it("ignores x-forwarded-for even when the proxy is trusted", async () => {
    const headers = (n: number) => ({ ...as("5.5.5.5"), "x-forwarded-for": `7.7.7.${n}` });
    for (let i = 0; i < 2; i++) await get("/limited", headers(i));
    expect((await get("/limited", headers(99))).status).toBe(429);
  });

  it("does not limit endpoints that didn't opt in", async () => {
    for (let i = 0; i < 5; i++) expect((await get("/open", as("4.4.4.4"))).status).toBe(200);
  });
});

describe("RateLimit middleware on authenticated routes", () => {
  class AuthedApi extends HttpApi.make("authed").add(
    HttpApiGroup.make("things").add(
      HttpApiEndpoint.get("mine", "/mine", { success: Schema.String })
        .middleware(RateLimit)
        .middleware(Authorization)
        .annotate(RateLimitPolicy, { limit: 2, window: "1 minute" }),
    ),
  ) {}

  // Stands in for the Better Auth session lookup: the user is whoever x-user names.
  const FakeAuthorization = Layer.succeed(
    Authorization,
    Authorization.of((httpEffect) =>
      Effect.gen(function* () {
        const request = yield* HttpServerRequest.HttpServerRequest;
        const id = UserId.make(request.headers["x-user"] ?? "nobody");
        const user = new User({ id, email: `${id}@example.test`, name: id });
        return yield* Effect.provideService(httpEffect, CurrentUser, user);
      }),
    ),
  );

  const AuthedHandlers = HttpApiBuilder.group(AuthedApi, "things", (handlers) =>
    Effect.succeed(handlers.handle("mine", () => Effect.succeed("ok"))),
  );

  const authed = HttpRouter.toWebHandler(
    HttpApiBuilder.layer(AuthedApi).pipe(
      Layer.provide(AuthedHandlers),
      Layer.provide(FakeAuthorization),
      Layer.provide(RateLimitLive),
      Layer.provide(AppConfig.layerTest({ trustProxy: true })),
      Layer.provide(HttpServer.layerServices),
    ),
    { disableLogger: true },
  );
  afterAll(() => authed.dispose());

  const call = (user: string, ip: string) =>
    authed
      .handler(new Request("http://localhost/mine", { headers: { "x-user": user, ...as(ip) } }))
      .then((res) => res.status);

  it("keys the limit by user, not by address", async () => {
    expect(await call("alice", "6.6.6.1")).toBe(200);
    expect(await call("alice", "6.6.6.2")).toBe(200);
    // Changing address doesn't buy alice a fresh budget...
    expect(await call("alice", "6.6.6.3")).toBe(429);
    // ...and another user behind the same address isn't limited by her traffic.
    expect(await call("bob", "6.6.6.1")).toBe(200);
  });
});
