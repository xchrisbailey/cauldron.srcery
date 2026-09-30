import { Effect } from "effect";
import { HttpEffect, HttpRouter } from "effect/http";
import { Auth } from "../Auth.ts";

// Mounts Better Auth's web handler beside the HttpApi routes.
export const AuthRoute = HttpRouter.use(
  Effect.fn(function* (router) {
    const auth = yield* Auth;
    const handler = HttpEffect.fromWebHandler(auth.handler);
    yield* router.add("*", "/v1/auth/*", handler);
  }),
);
