import { Effect, Layer } from "effect";
import { HttpRouter } from "effect/http";
import { AppConfig } from "./AppConfig.ts";
import { Auth } from "./Auth.ts";
import { Db } from "./Db.ts";
import { ApiRoutes } from "./http/Api.ts";
import { AuthRoute } from "./http/AuthRoute.ts";
import { RateLimitLive } from "./http/RateLimit.ts";
import { RequestId } from "./http/RequestId.ts";
import { Mailer } from "./Mailer.ts";

const Cors = Layer.unwrap(
  Effect.gen(function* () {
    const { publicUrl } = yield* AppConfig;
    return HttpRouter.cors({
      allowedOrigins: [publicUrl],
      credentials: true,
      exposedHeaders: ["x-request-id", "set-auth-token"],
    });
  }),
);

/** Every route, needing only the external services (config, database, email). */
export const Routes = Layer.mergeAll(ApiRoutes, AuthRoute, RequestId, Cors).pipe(
  Layer.provide([Auth.layer, RateLimitLive]),
);

/** The external services for a real run. Tests swap in `Db.layerTest` and `Mailer.layerTest`. */
export const Services = Layer.mergeAll(Db.layer, Mailer.layer);
