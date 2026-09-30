import { Authorization, CurrentUser } from "@cauldron/api-spec";
import { copy, Unauthorized, User, UserId } from "@cauldron/shared";
import { Effect, Layer } from "effect";
import { HttpServerRequest } from "effect/http";
import { Auth } from "../Auth.ts";

export const AuthorizationLive = Layer.effect(
  Authorization,
  Effect.gen(function* () {
    const auth = yield* Auth;
    return Authorization.of(
      Effect.fn("Authorization")(function* (httpEffect) {
        const request = yield* HttpServerRequest.HttpServerRequest;
        const headers = new Headers(request.headers as Record<string, string>);
        // getSession resolves null when signed out; a rejection is an outage, not a 401.
        const session = yield* Effect.promise(() => auth.api.getSession({ headers }));
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
