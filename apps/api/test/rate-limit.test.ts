import { RateLimit, RateLimitPolicy } from "@cauldron/api-spec";
import { Effect, Layer, Schema } from "effect";
import { HttpRouter, HttpServer } from "effect/http";
import { HttpApi, HttpApiBuilder, HttpApiEndpoint, HttpApiGroup } from "effect/http-api";
import { afterAll, describe, expect, it } from "vite-plus/test";
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

const { handler, dispose } = HttpRouter.toWebHandler(
  HttpApiBuilder.layer(TestApi).pipe(
    Layer.provide(Handlers),
    Layer.provide(RateLimitLive),
    Layer.provide(HttpServer.layerServices),
  ),
  { disableLogger: true },
);
afterAll(() => dispose());

const get = (path: string, ip?: string) =>
  handler(
    new Request(`http://localhost${path}`, {
      headers: ip ? { "x-forwarded-for": `${ip}, 10.0.0.1` } : {},
    }),
  );

describe("RateLimit middleware", () => {
  it("allows the policy's limit, then answers 429 with the error body", async () => {
    expect((await get("/limited", "1.1.1.1")).status).toBe(200);
    expect((await get("/limited", "1.1.1.1")).status).toBe(200);
    const res = await get("/limited", "1.1.1.1");
    expect(res.status).toBe(429);
    const body = (await res.json()) as any;
    expect(body.error.code).toBe("too_many_requests");
    expect(body.error.message).toEqual(expect.any(String));
    expect(body.error.retryAfterSeconds).toBeGreaterThanOrEqual(1);
    expect(body.error.retryAfterSeconds).toBeLessThanOrEqual(60);
  });

  it("keeps a separate budget per client IP", async () => {
    for (let i = 0; i < 3; i++) await get("/limited", "2.2.2.2");
    expect((await get("/limited", "2.2.2.2")).status).toBe(429);
    expect((await get("/limited", "3.3.3.3")).status).toBe(200);
  });

  it("does not limit endpoints that didn't opt in", async () => {
    for (let i = 0; i < 5; i++) expect((await get("/open", "4.4.4.4")).status).toBe(200);
  });
});
