import { Effect, Layer, ManagedRuntime, Ref } from "effect";
import { HttpRouter, HttpServer } from "effect/http";
import type { AppConfig } from "../src/AppConfig.ts";
import { Routes } from "../src/App.ts";
import { type Email, MailerOutbox } from "../src/Mailer.ts";
import { TestServices, url, WEB_ORIGIN } from "./helpers.ts";

/**
 * Like `makeTestApi`, but keeps a handle on the mail outbox. The router and a
 * small runtime are built from the same layer instances through one memo map, so
 * the `MailerOutbox` the runtime reads is the one Better Auth's mailer writes to.
 */
export const makeAuthApi = (
  config: Partial<AppConfig["Service"]> = {},
  // oxlint-disable-next-line typescript/no-explicit-any
  routes: Layer.Layer<never, never, any> = Routes,
  remote: Parameters<typeof TestServices>[1] = {},
) => {
  const memoMap = Layer.makeMemoMapUnsafe();
  const services = TestServices(config, remote);
  const web = HttpRouter.toWebHandler(
    routes.pipe(Layer.provide(services), Layer.provide(HttpServer.layerServices)) as Layer.Layer<
      never,
      never,
      HttpRouter.HttpRouter
    >,
    { disableLogger: true, memoMap },
  );
  const runtime = ManagedRuntime.make(services, { memoMap });

  const outbox = (): Promise<ReadonlyArray<Email>> =>
    runtime.runPromise(
      Effect.gen(function* () {
        return yield* Ref.get(yield* MailerOutbox);
      }),
    );

  /**
   * Better Auth's mail is sent in a forked fiber, not awaited by the request, so
   * poll until the outbox holds `count` emails (or fail after a couple of seconds).
   */
  const waitForOutbox = async (count: number): Promise<ReadonlyArray<Email>> => {
    for (let i = 0; i < 200; i++) {
      const sent = await outbox();
      if (sent.length >= count) return sent;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    throw new Error(`expected ${count} emails in the outbox, got ${(await outbox()).length}`);
  };

  /** For asserting that nothing was sent: give a forked send time to land first. */
  const settle = (ms = 150) => new Promise((resolve) => setTimeout(resolve, ms));

  const send = (path: string, init: RequestInit = {}) =>
    web.handler(new Request(url(path), { redirect: "manual", ...init }));

  const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
    send(path, {
      method: "POST",
      headers: { "content-type": "application/json", origin: WEB_ORIGIN, ...headers },
      body: JSON.stringify(body),
    });

  /** Path and query of the first link in an email, to feed back into the handler. */
  const linkIn = (email: Email) => {
    const link = /https?:\/\/\S+/.exec(email.text)?.[0];
    if (!link) throw new Error(`no link in email: ${email.text}`);
    const parsed = new URL(link);
    return parsed.pathname + parsed.search;
  };

  return {
    handler: web.handler,
    send,
    post,
    outbox,
    waitForOutbox,
    settle,
    linkIn,
    dispose: async () => {
      await web.dispose();
      await runtime.dispose();
    },
  };
};

export type AuthApi = ReturnType<typeof makeAuthApi>;

export const cookieOf = (res: Response): string | undefined => {
  const cookie = res.headers.getSetCookie().find((c) => c.startsWith("better-auth.session_token="));
  const pair = cookie?.split(";")[0];
  // A cleared cookie has an empty value.
  return pair && !pair.endsWith("=") ? pair : undefined;
};
