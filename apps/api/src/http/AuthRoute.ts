import { copy } from "@cauldron/shared";
import { Effect } from "effect";
import { HttpEffect, HttpRouter, HttpServerRequest } from "effect/http";
import { RateLimiter } from "effect/persistence";
import { AppConfig } from "../AppConfig.ts";
import { Auth } from "../Auth.ts";
import { resolveClientIp } from "./ClientIp.ts";
import { consumeOrReject } from "./RateLimit.ts";

/**
 * The Better Auth endpoints that check a password, send email or start a
 * sign-in (each writes a row), each limited per client address.
 */
export const AUTH_RATE_LIMITED_PATHS = new Set(
  [
    "/sign-in/email",
    "/sign-up/email",
    "/request-password-reset",
    "/send-verification-email",
    "/change-password",
    "/verify-password",
    "/sign-in/social",
    "/sign-in/oauth2",
  ].map((path) => `/v1/auth${path}`),
);

export const AUTH_RATE_LIMIT = { limit: 5, window: "1 minute" } as const;

// Mounts Better Auth's web handler beside the HttpApi routes.
export const AuthRoute = HttpRouter.use(
  Effect.fn(function* (router) {
    const auth = yield* Auth;
    const { trustProxy, authRateLimit } = yield* AppConfig;
    const limiter = yield* RateLimiter.RateLimiter;
    const handler = HttpEffect.fromWebHandler(auth.handler);
    const limited = Effect.gen(function* () {
      const request = yield* HttpServerRequest.HttpServerRequest;
      const path = new URL(request.url, "http://localhost").pathname.replace(/\/+$/, "");
      if (request.method !== "POST" || !AUTH_RATE_LIMITED_PATHS.has(path)) return yield* handler;
      const rejected = yield* consumeOrReject(limiter, {
        key: `auth:${path}:ip:${resolveClientIp(request, trustProxy)}`,
        ...AUTH_RATE_LIMIT,
        // Better Auth's own error shape, which its client reads.
        tooManyRequests: () => ({
          code: "TOO_MANY_REQUESTS",
          message: copy.errors.tooManyRequests.text,
        }),
      });
      return rejected ?? (yield* handler);
    });
    yield* router.add("*", "/v1/auth/*", authRateLimit ? limited : handler);
  }),
);
