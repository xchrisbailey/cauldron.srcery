import { CurrentUser, RateLimit, RateLimitPolicy, TooManyRequestsError } from "@cauldron/api-spec";
import { copy, TooManyRequests } from "@cauldron/shared";
import { Context, Duration, Effect, Layer, Option, Schema } from "effect";
import { HttpServerRequest, HttpServerResponse } from "effect/http";
import { RateLimiter } from "effect/persistence";
import { AppConfig } from "../AppConfig.ts";
import { resolveClientIp } from "./ClientIp.ts";
import { layerStoreMemoryBounded } from "./RateLimitStore.ts";

const encodeTooManyRequests = Schema.encodeSync(TooManyRequestsError);

/**
 * Takes one request from `key`'s fixed-window budget. Answers a 429 response
 * (with Retry-After and the given body) when the budget is spent, or undefined
 * to let the request through. Shared by the HttpApi middleware and the Better
 * Auth route, so both use one store and one window rule.
 */
export const consumeOrReject = (
  limiter: RateLimiter.RateLimiter,
  options: {
    readonly key: string;
    readonly limit: number;
    readonly window: Duration.Input;
    readonly tooManyRequests: (retryAfterSeconds: number) => unknown;
  },
): Effect.Effect<HttpServerResponse.HttpServerResponse | undefined> =>
  limiter
    .consume({
      algorithm: "fixed-window",
      onExceeded: "fail",
      key: options.key,
      limit: options.limit,
      window: options.window,
    })
    .pipe(
      Effect.as(undefined),
      Effect.catchTag("RateLimiterError", (error) => {
        // A broken limiter store shouldn't take the route down.
        if (error.reason._tag !== "RateLimitExceeded") return Effect.undefined;
        const retryAfterSeconds = Math.max(
          1,
          Math.ceil(Duration.toSeconds(error.reason.retryAfter)),
        );
        // Answered here rather than failed, so the response can carry Retry-After.
        return Effect.succeed(
          HttpServerResponse.jsonUnsafe(options.tooManyRequests(retryAfterSeconds), {
            status: 429,
            headers: { "retry-after": String(retryAfterSeconds) },
          }),
        );
      }),
    );

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
        const rejected = yield* consumeOrReject(limiter, {
          key: `${group.identifier}:${endpoint.identifier}:${subject}`,
          limit: policy.limit,
          window: policy.window,
          tooManyRequests: (retryAfterSeconds) =>
            encodeTooManyRequests(
              new TooManyRequests({ message: copy.errors.tooManyRequests.text, retryAfterSeconds }),
            ),
        });
        return rejected ?? (yield* httpEffect);
      }),
    );
  }),
);

/**
 * The middleware plus the limiter and its in-memory store. The limiter is also
 * exposed, for the Better Auth route. Swap the store layer for Redis when the
 * API scales out.
 */
export const RateLimitLive = RateLimitMiddleware.pipe(
  Layer.provideMerge(RateLimiter.layer),
  Layer.provide(layerStoreMemoryBounded),
);
