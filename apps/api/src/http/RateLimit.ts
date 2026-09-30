import { RateLimit, RateLimitPolicy } from "@cauldron/api-spec";
import { copy, TooManyRequests } from "@cauldron/shared";
import { Context, Duration, Effect, Layer, Option } from "effect";
import { HttpServerRequest } from "effect/http";
import { RateLimiter } from "effect/persistence";

/** First `x-forwarded-for` entry, else the socket's remote address, else "unknown". */
export const clientIp = (request: HttpServerRequest.HttpServerRequest): string => {
  const forwarded = request.headers["x-forwarded-for"]?.split(",")[0]?.trim();
  if (forwarded) return forwarded;
  return Option.getOrElse(request.remoteAddress, () => "unknown");
};

export const RateLimitMiddleware = Layer.effect(
  RateLimit,
  Effect.gen(function* () {
    const limiter = yield* RateLimiter.RateLimiter;
    return RateLimit.of((httpEffect, { endpoint, group }) =>
      Effect.gen(function* () {
        const request = yield* HttpServerRequest.HttpServerRequest;
        const policy = Context.get(endpoint.annotations, RateLimitPolicy);
        yield* limiter
          .consume({
            algorithm: "fixed-window",
            onExceeded: "fail",
            key: `${group.identifier}:${endpoint.identifier}:${clientIp(request)}`,
            limit: policy.limit,
            window: policy.window,
          })
          .pipe(
            Effect.catchTag("RateLimiterError", (error) =>
              error.reason._tag === "RateLimitExceeded"
                ? Effect.fail(
                    new TooManyRequests({
                      message: copy.errors.tooManyRequests.text,
                      retryAfterSeconds: Math.max(
                        1,
                        Math.ceil(Duration.toSeconds(error.reason.retryAfter)),
                      ),
                    }),
                  )
                : // A broken limiter store shouldn't take the route down.
                  Effect.void,
            ),
          );
        return yield* httpEffect;
      }),
    );
  }),
);

/** The middleware plus its in-memory store. Swap the store layer for Redis when the API scales out. */
export const RateLimitLive = RateLimitMiddleware.pipe(
  Layer.provide(RateLimiter.layer),
  Layer.provide(RateLimiter.layerStoreMemory),
);
