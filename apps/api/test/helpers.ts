import { schema } from "@cauldron/db";
import { UserId } from "@cauldron/shared";
import { Effect, Layer } from "effect";
import { HttpRouter, HttpServer } from "effect/http";
import { AppConfig } from "../src/AppConfig.ts";
import { Routes } from "../src/App.ts";
import { Db } from "../src/Db.ts";
import { RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { Mailer } from "../src/Mailer.ts";
import { Photos } from "../src/Photos.ts";
import { RemoteFetch } from "../src/RemoteFetch.ts";
import { Storage } from "../src/Storage.ts";

export const WEB_ORIGIN = "http://localhost:3000";

/**
 * Test versions of every external service: a fresh migrated database (real
 * Postgres when DATABASE_URL is set, as in CI; in-memory PGlite otherwise) and
 * an in-memory mail outbox. No model is configured unless a test passes a
 * fake one (`RecipeExtractor.layerTest`).
 */
export const TestServices = (
  config: Partial<AppConfig["Service"]> = {},
  remote: Parameters<typeof RemoteFetch.layerTest>[0] = {},
  extractor: Layer.Layer<RecipeExtractor> = RecipeExtractor.layerNone,
) =>
  Layer.mergeAll(
    Db.layerTest,
    Mailer.layerTest,
    Storage.layerTest,
    RemoteFetch.layerTest(remote),
    extractor,
  ).pipe(Layer.provideMerge(AppConfig.layerTest(config)));

/**
 * What `distill` reads through, on the test services: canned responses for
 * the network, a fake model, and Photos over the test database and storage.
 */
export const DistillServices = (
  remote: Parameters<typeof RemoteFetch.layerTest>[0] = {},
  extractor: Layer.Layer<RecipeExtractor> = RecipeExtractor.layerNone,
) => Photos.layer.pipe(Layer.provideMerge(TestServices({}, remote, extractor)));

/** A new user to own what a test creates, without going through sign-up. */
export const makeOwner = Effect.fn("makeOwner")(function* () {
  const db = yield* Db;
  const id = `u_${crypto.randomUUID()}`;
  yield* db.use((d) =>
    d.insert(schema.user).values({ id, name: "Cook", email: `${id}@example.test` }),
  );
  return UserId.make(id);
});

/** Builds the full API (HttpApi routes + Better Auth) as an in-process fetch handler. */
export const makeTestApi = (config: Partial<AppConfig["Service"]> = {}) =>
  HttpRouter.toWebHandler(
    Routes.pipe(Layer.provide(TestServices(config)), Layer.provide(HttpServer.layerServices)),
    { disableLogger: true },
  );

export const url = (path: string) => new URL(path, WEB_ORIGIN).toString();

export const sessionCookie = (res: Response): string => {
  const cookie = res.headers.getSetCookie().find((c) => c.startsWith("better-auth.session_token="));
  if (!cookie) throw new Error(`no session cookie (status ${res.status})`);
  return cookie.split(";")[0]!;
};
