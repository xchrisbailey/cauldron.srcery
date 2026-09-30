import { copy } from "@cauldron/shared";
import { Effect, Layer, Schema } from "effect";
import { HttpRouter, HttpServer, HttpServerResponse } from "effect/http";
import { HttpApi, HttpApiBuilder, HttpApiEndpoint, HttpApiGroup } from "effect/http-api";
import { afterAll, describe, expect, it } from "vite-plus/test";
import { AppConfig } from "../src/AppConfig.ts";
import { Routes } from "../src/App.ts";
import { Db, DbError } from "../src/Db.ts";
import { ErrorShape } from "../src/http/ErrorShape.ts";
import { Mailer } from "../src/Mailer.ts";
import { WEB_ORIGIN, makeTestApi, url } from "./helpers.ts";
import { NotFoundError } from "@cauldron/api-spec";
import { NotFound } from "@cauldron/shared";

const app = makeTestApi();
afterAll(() => app.dispose());

describe("system endpoints", () => {
  it("GET /v1/health reports ok", async () => {
    const res = await app.handler(new Request(url("/v1/health")));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "ok", database: "ok" });
  });

  it("GET /v1/version reports the configured version and no commit", async () => {
    const res = await app.handler(new Request(url("/v1/version")));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ version: "0.0.0-test", commit: null });
  });

  it("GET /v1/account/me is 401 when anonymous", async () => {
    const res = await app.handler(new Request(url("/v1/account/me")));
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({
      error: { code: "unauthorized", message: copy.errors.unauthorized.text },
    });
  });

  it("unknown routes get the standard 404 body", async () => {
    const res = await app.handler(
      new Request(url("/v1/nope"), { headers: { "x-request-id": "abc12345-req" } }),
    );
    expect(res.status).toBe(404);
    expect(res.headers.get("x-request-id")).toBe("abc12345-req");
    expect(await res.json()).toEqual({
      error: { code: "not_found", message: copy.errors.notFound.text },
    });
  });
});

describe("request ids", () => {
  it("adds one when absent", async () => {
    const res = await app.handler(new Request(url("/v1/version")));
    expect(res.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("echoes a well-formed incoming id", async () => {
    const res = await app.handler(
      new Request(url("/v1/version"), { headers: { "x-request-id": "abc12345-req" } }),
    );
    expect(res.headers.get("x-request-id")).toBe("abc12345-req");
  });

  it("puts the id on error responses too", async () => {
    const res = await app.handler(
      new Request(url("/v1/account/me"), { headers: { "x-request-id": "abc12345-req" } }),
    );
    expect(res.status).toBe(401);
    expect(res.headers.get("x-request-id")).toBe("abc12345-req");
  });

  it.each(["bad id!", "short", "x".repeat(129)])("replaces the malformed id %j", async (bad) => {
    const res = await app.handler(
      new Request(url("/v1/version"), { headers: { "x-request-id": bad } }),
    );
    const id = res.headers.get("x-request-id");
    expect(id).not.toBe(bad);
    expect(id).toMatch(/^[0-9a-f-]{36}$/);
  });
});

describe("CORS", () => {
  const preflight = (origin: string) =>
    app.handler(
      new Request(url("/v1/version"), {
        method: "OPTIONS",
        headers: { origin, "access-control-request-method": "GET" },
      }),
    );

  it("allows the web origin with credentials", async () => {
    const res = await preflight(WEB_ORIGIN);
    expect(res.headers.get("access-control-allow-origin")).toBe(WEB_ORIGIN);
    expect(res.headers.get("access-control-allow-credentials")).toBe("true");
  });

  it("does not allow other origins", async () => {
    const res = await preflight("https://evil.example");
    expect(res.headers.get("access-control-allow-origin")).not.toBe("https://evil.example");
    expect(res.headers.get("access-control-allow-origin")).not.toBe("*");
  });
});

describe("health when the database is down", () => {
  const FailingPing = Layer.effect(
    Db,
    Effect.gen(function* () {
      const db = yield* Db;
      return Db.of({ ...db, ping: Effect.fail(new DbError({ cause: "down" })) });
    }),
  ).pipe(Layer.provide(Db.layerTest));

  const down = HttpRouter.toWebHandler(
    Routes.pipe(
      Layer.provide(
        Layer.mergeAll(FailingPing, Mailer.layerTest).pipe(
          Layer.provideMerge(AppConfig.layerTest()),
        ),
      ),
      Layer.provide(HttpServer.layerServices),
    ),
    { disableLogger: true },
  );
  afterAll(() => down.dispose());

  it("answers 503 unavailable", async () => {
    const res = await down.handler(new Request(url("/v1/health")));
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({
      error: { code: "unavailable", message: copy.errors.unavailable.text },
    });
  });
});

describe("ErrorShape", () => {
  class TestApi extends HttpApi.make("shape").add(
    HttpApiGroup.make("things").add(
      HttpApiEndpoint.post("create", "/create", {
        payload: Schema.Struct({ name: Schema.String }),
        success: Schema.String,
      }),
      HttpApiEndpoint.get("missing", "/missing", { success: Schema.String, error: NotFoundError }),
    ),
  ) {}

  const Handlers = HttpApiBuilder.group(TestApi, "things", (handlers) =>
    Effect.succeed(
      handlers
        .handle("create", ({ payload }) => Effect.succeed(payload.name))
        .handle("missing", () => Effect.fail(new NotFound({ message: "custom message" }))),
    ),
  );

  const Boom = HttpRouter.use((router) =>
    router.add("GET", "/boom", Effect.die(new Error("kaboom"))),
  );
  const Teapot = HttpRouter.use((router) =>
    router.add(
      "GET",
      "/teapot",
      Effect.succeed(HttpServerResponse.text("short and stout", { status: 418 })),
    ),
  );

  const shape = HttpRouter.toWebHandler(
    Layer.mergeAll(
      HttpApiBuilder.layer(TestApi).pipe(Layer.provide(Handlers)),
      Boom,
      Teapot,
      ErrorShape,
    ).pipe(Layer.provide(HttpServer.layerServices)),
    { disableLogger: true },
  );
  afterAll(() => shape.dispose());

  const call = (path: string, init?: RequestInit) =>
    shape.handler(new Request(`http://localhost${path}`, init));

  it("turns a defect into a 500 with the internal body", async () => {
    const res = await call("/boom");
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({
      error: { code: "internal", message: copy.errors.internal.text },
    });
  });

  it("turns a payload decode failure into a 400 invalid_request", async () => {
    const res = await call("/create", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ name: 1 }),
    });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({
      error: { code: "invalid_request", message: copy.errors.invalidRequest.text },
    });
  });

  it("accepts a valid payload", async () => {
    const res = await call("/create", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ name: "ok" }),
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toBe("ok");
  });

  it("leaves a domain error from an endpoint untouched", async () => {
    const res = await call("/missing");
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: "not_found", message: "custom message" } });
  });

  it("leaves a response that already has a body untouched", async () => {
    const res = await call("/teapot");
    expect(res.status).toBe(418);
    expect(await res.text()).toBe("short and stout");
  });
});
