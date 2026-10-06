import { copy } from "@cauldron/shared";
import { Effect, Option, Schema } from "effect";
import { HttpEffect, HttpRouter, HttpServerRequest } from "effect/http";
import { RateLimiter } from "effect/persistence";
import { AppConfig } from "../AppConfig.ts";
import { Auth } from "../Auth.ts";
import { resolveClientIp } from "./ClientIp.ts";
import { consumeOrReject } from "./RateLimit.ts";

/**
 * The Better Auth endpoints that check a password, send email, start a sign-in
 * or delete an account (each writes a row), each limited per client address.
 */
export const AUTH_RATE_LIMITED_PATHS = new Set(
  [
    "/sign-in/email",
    "/sign-up/email",
    "/request-password-reset",
    "/send-verification-email",
    "/change-password",
    "/verify-password",
    "/delete-user",
    "/sign-in/social",
    "/sign-in/oauth2",
  ].map((path) => `/v1/auth${path}`),
);

/** Per client address, per endpoint. */
export const AUTH_RATE_LIMIT = { limit: 5, window: "1 minute" } as const;

/**
 * The password-checking endpoints also get a per-account budget, so a guesser
 * who rotates addresses still can't try many passwords against one account.
 * `/sign-in/email` is keyed on the (normalised) email in the body; the others
 * carry no email and are keyed on the signed-in user. Every attempt counts,
 * not only failures: simpler, and 10 tries in 15 minutes is generous for a person.
 */
export const AUTH_ACCOUNT_RATE_LIMIT = { limit: 10, window: "15 minutes" } as const;

const EMAIL_KEYED_PATH = "/v1/auth/sign-in/email";
const SESSION_KEYED_PATHS = new Set(
  ["/change-password", "/verify-password", "/delete-user"].map((path) => `/v1/auth${path}`),
);

// Keys and logs never hold a raw email or token, only this digest.
const sha256Hex = (input: string) =>
  Effect.promise(async () => {
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
    return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
  });

const decodeSignInBody = Schema.decodeUnknownOption(
  Schema.fromJsonString(Schema.Struct({ email: Schema.String })),
);

// The email in a sign-in body, trimmed and lowercased, read the way Better Auth
// will read it: JSON, or a form post. Anything else gives none, and Better Auth
// answers it.
const emailFromBody = (text: string, contentType: string | undefined): string | undefined => {
  const raw = contentType?.toLowerCase().includes("application/x-www-form-urlencoded")
    ? (new URLSearchParams(text).get("email") ?? undefined)
    : Option.getOrUndefined(decodeSignInBody(text))?.email;
  const email = raw?.trim().toLowerCase();
  return email === "" ? undefined : email;
};

// Better Auth's own error shape, which its client reads.
const tooManyRequests = () => ({
  code: "TOO_MANY_REQUESTS",
  message: copy.errors.tooManyRequests.text,
});

// Mounts Better Auth's web handler beside the HttpApi routes.
export const AuthRoute = HttpRouter.use(
  Effect.fn(function* (router) {
    const auth = yield* Auth;
    const { trustProxy, authRateLimit } = yield* AppConfig;
    const limiter = yield* RateLimiter.RateLimiter;
    const handler = HttpEffect.fromWebHandler(auth.handler);

    // Hands Better Auth a request rebuilt from already-read body text. On the
    // server the Effect request wraps the web Request itself, and
    // `fromWebHandler` passes that same object on, so once `request.text` has
    // consumed its body the handler would see it empty. Rebuilding is safe.
    const handlerWithBody = (text: string) =>
      HttpEffect.fromWebHandler((original) =>
        auth.handler(
          new Request(original.url, {
            method: original.method,
            headers: original.headers,
            body: text,
            signal: original.signal,
          }),
        ),
      );

    // The signed-in user, resolved by Better Auth itself (cookie or bearer, with
    // its own cookie names, signatures and decoding), so the key can't be varied
    // by dressing one session up differently. No session, no key: Better Auth
    // answers 401 without checking a password.
    const sessionUserId = (request: HttpServerRequest.HttpServerRequest) =>
      Effect.tryPromise(() =>
        auth.api.getSession({
          headers: new Headers(request.headers),
          query: { disableRefresh: true },
        }),
      ).pipe(
        Effect.map((session) => session?.user.id),
        Effect.orElseSucceed(() => undefined),
      );

    // The account budget's subject, or undefined when there's nothing to key on.
    const accountKey = Effect.fn("AuthRoute.accountKey")(function* (
      request: HttpServerRequest.HttpServerRequest,
      path: string,
      text: string | undefined,
    ) {
      if (path === EMAIL_KEYED_PATH) {
        const email =
          text === undefined ? undefined : emailFromBody(text, request.headers["content-type"]);
        return email === undefined ? undefined : `email:${yield* sha256Hex(email)}`;
      }
      if (!SESSION_KEYED_PATHS.has(path)) return undefined;
      const userId = yield* sessionUserId(request);
      return userId === undefined ? undefined : `user:${userId}`;
    });

    const limited = Effect.gen(function* () {
      const request = yield* HttpServerRequest.HttpServerRequest;
      const path = new URL(request.url, "http://localhost").pathname.replace(/\/+$/, "");
      if (request.method !== "POST" || !AUTH_RATE_LIMITED_PATHS.has(path)) return yield* handler;
      // Address first, so a blocked address doesn't burn the account budget.
      const addressRejected = yield* consumeOrReject(limiter, {
        key: `auth:${path}:ip:${resolveClientIp(request, trustProxy)}`,
        ...AUTH_RATE_LIMIT,
        tooManyRequests,
      });
      if (addressRejected) return addressRejected;

      const text =
        path === EMAIL_KEYED_PATH
          ? yield* request.text.pipe(Effect.orElseSucceed(() => ""))
          : undefined;
      const subject = yield* accountKey(request, path, text);
      if (subject !== undefined) {
        const accountRejected = yield* consumeOrReject(limiter, {
          key: `auth:${path}:${subject}`,
          ...AUTH_ACCOUNT_RATE_LIMIT,
          tooManyRequests,
        });
        if (accountRejected) return accountRejected;
      }
      return text === undefined ? yield* handler : yield* handlerWithBody(text);
    });
    yield* router.add("*", "/v1/auth/*", authRateLimit ? limited : handler);
  }),
);
