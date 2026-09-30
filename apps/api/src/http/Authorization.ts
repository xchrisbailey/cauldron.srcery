import { Authorization, CurrentUser } from "@cauldron/api-spec";
import { Unauthorized, User, UserId } from "@cauldron/shared";
import { Effect, Layer } from "effect";
import { HttpServerRequest } from "effect/http";
import { Auth } from "../Auth.ts";

export const AuthorizationLive = Layer.effect(
  Authorization,
  Effect.gen(function* () {
    const auth = yield* Auth;
    return Authorization.of((httpEffect) =>
      Effect.gen(function* () {
        const request = yield* HttpServerRequest.HttpServerRequest;
        const headers = new Headers(request.headers as Record<string, string>);
        const session = yield* Effect.tryPromise(() => auth.api.getSession({ headers })).pipe(
          Effect.orElseSucceed(() => null),
        );
        if (!session) {
          return yield* new Unauthorized({ message: "Sign in to continue." });
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
