import { Layer } from "effect";
import { HttpRouter, HttpServer } from "effect/http";
import { AppConfig } from "../src/AppConfig.ts";
import { Routes } from "../src/App.ts";
import { Db } from "../src/Db.ts";
import { Mailer } from "../src/Mailer.ts";

export const WEB_ORIGIN = "http://localhost:3000";

/**
 * Test versions of every external service: a fresh migrated database (real
 * Postgres when DATABASE_URL is set, as in CI; in-memory PGlite otherwise) and
 * an in-memory mail outbox.
 */
export const TestServices = (config: Partial<AppConfig["Service"]> = {}) =>
  Layer.mergeAll(Db.layerTest, Mailer.layerTest).pipe(
    Layer.provideMerge(AppConfig.layerTest(config)),
  );

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
