import { Authorization, CurrentUser } from "@cauldron/api-spec";
import { copy, Forbidden, Unauthorized, User, UserId } from "@cauldron/shared";
import { Effect, Layer } from "effect";
import { HttpServerRequest } from "effect/http";
import { AppConfig } from "../AppConfig.ts";
import { Auth } from "../Auth.ts";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export const AuthorizationLive = Layer.effect(
  Authorization,
  Effect.gen(function* () {
    const auth = yield* Auth;
    const { publicUrl } = yield* AppConfig;
    const webOrigin = new URL(publicUrl).origin;
    return Authorization.of(
      Effect.fn("Authorization")(function* (httpEffect) {
        const request = yield* HttpServerRequest.HttpServerRequest;
        const bearer = request.headers["authorization"]?.toLowerCase().startsWith("bearer ");
        // Cookies ride along on cross-site requests; bearer tokens don't. Any request
        // that carries a cookie gets the Origin check (a bearer header alongside a
        // cookie mustn't skip it); only bearer with no cookie is exempt.
        const cookie = Boolean(request.headers["cookie"]);
        if (
          (cookie || !bearer) &&
          !SAFE_METHODS.has(request.method) &&
          request.headers["origin"] !== webOrigin
        ) {
          return yield* new Forbidden({ message: copy.errors.crossSite.text });
        }
        const headers = new Headers(request.headers as Record<string, string>);
        // getSession resolves null when signed out; a rejection is an outage, not a 401.
        // The signed session_data cookie would otherwise satisfy getSession for up to
        // cookieCache.maxAge without touching the database, so a replayed cookie would
        // outlive sign-out and account deletion. Always check the session row.
        const session = yield* Effect.promise(() =>
          auth.api.getSession({ headers, query: { disableCookieCache: true } }),
        );
        if (!session) {
          return yield* new Unauthorized({ message: copy.errors.unauthorized.text });
        }
        const user = new User({
          id: UserId.make(session.user.id),
          email: session.user.email,
          name: session.user.name,
        });
        return yield* Effect.provideService(httpEffect, CurrentUser, user);
      }),
    );
  }),
);
