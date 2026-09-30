import { CurrentUser, RateLimit, RateLimitPolicy, TooManyRequestsError } from "@cauldron/api-spec";
import { copy, TooManyRequests } from "@cauldron/shared";
import { Context, Duration, Effect, Layer, Option, Schema } from "effect";
import { HttpServerRequest, HttpServerResponse } from "effect/http";
import { RateLimiter } from "effect/persistence";
import { AppConfig } from "../AppConfig.ts";
import { resolveClientIp } from "./ClientIp.ts";
import { layerStoreMemoryBounded } from "./RateLimitStore.ts";

const encodeTooManyRequests = Schema.encodeSync(TooManyRequestsError);

export const RateLimitMiddleware = Layer.effect(
  RateLimit,
  Effect.gen(function* () {
    const limiter = yield* RateLimiter.RateLimiter;
    const { trustProxy } = yield* AppConfig;
    return RateLimit.of((httpEffect, { endpoint, group }) =>
      Effect.gen(function* () {
        const request = yield* HttpServerRequest.HttpServerRequest;
        const policy = Context.get(endpoint.annotations, RateLimitPolicy);
        // Signed-in requests are limited per user (an address can be shared or
        // rotate); anonymous ones per client address.
        const user = yield* Effect.serviceOption(CurrentUser);
        const subject = Option.match(user, {
          onNone: () => `ip:${resolveClientIp(request, trustProxy)}`,
          onSome: (u) => `user:${u.id}`,
        });
        const rejected = yield* limiter
          .consume({
            algorithm: "fixed-window",
            onExceeded: "fail",
            key: `${group.identifier}:${endpoint.identifier}:${subject}`,
            limit: policy.limit,
            window: policy.window,
          })
          .pipe(
            Effect.as(undefined as HttpServerResponse.HttpServerResponse | undefined),
            Effect.catchTag("RateLimiterError", (error) => {
              // A broken limiter store shouldn't take the route down.
              if (error.reason._tag !== "RateLimitExceeded") return Effect.void;
              const retryAfterSeconds = Math.max(
                1,
                Math.ceil(Duration.toSeconds(error.reason.retryAfter)),
              );
              // Answered here rather than failed, so the response can carry Retry-After.
              return Effect.succeed(
                HttpServerResponse.jsonUnsafe(
                  encodeTooManyRequests(
                    new TooManyRequests({
                      message: copy.errors.tooManyRequests.text,
                      retryAfterSeconds,
                    }),
                  ),
                  { status: 429, headers: { "retry-after": String(retryAfterSeconds) } },
                ),
              );
            }),
          );
        return rejected ?? (yield* httpEffect);
      }),
    );
  }),
);

/** The middleware plus its in-memory store. Swap the store layer for Redis when the API scales out. */
export const RateLimitLive = RateLimitMiddleware.pipe(
  Layer.provide(RateLimiter.layer),
  Layer.provide(layerStoreMemoryBounded),
);
