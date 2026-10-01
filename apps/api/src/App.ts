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
import { ImportWorker } from "./Imports.ts";
import { RecipeExtractor } from "./imports/RecipeExtractor.ts";
import { PhotoCleanup, Photos } from "./Photos.ts";
import { RemoteFetch } from "./RemoteFetch.ts";
import { Storage } from "./Storage.ts";

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

/** Every route, needing only the external services (config, database, email, storage, fetch, model). */
export const Routes = Layer.mergeAll(ApiRoutes, AuthRoute, RequestId, Cors).pipe(
  Layer.provide([Auth.layer, RateLimitLive]),
);

/** Background work that runs while the API is up: the import workers and the hourly photo cleanup. */
export const Jobs = Layer.merge(PhotoCleanup.pipe(Layer.provide(Photos.layer)), ImportWorker);

/**
 * The external services for a real run. Tests swap in `Db.layerTest`,
 * `Mailer.layerTest`, `Storage.layerTest`, `RemoteFetch.layerTest` and
 * `RecipeExtractor.layerTest`.
 */
export const Services = Layer.mergeAll(
  Db.layer,
  Mailer.layer,
  Storage.layer,
  RemoteFetch.layer,
  RecipeExtractor.layer,
);
