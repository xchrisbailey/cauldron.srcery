import { Duration, Effect, Layer } from "effect";
import { RateLimiter } from "effect/persistence";

const SWEEP_EVERY = Duration.toMillis("1 minute");

/**
 * In-memory limiter store whose fixed-window counters are evicted once their
 * window has passed. `RateLimiter.layerStoreMemory` never deletes a key, so
 * every client address ever seen would stay in memory for the life of the
 * process (token buckets have the same problem, and we only use fixed windows).
 *
 * The counter logic mirrors the stock store's `fixedWindow`; the other
 * algorithms are delegated to it unchanged. Replace with Redis when the API
 * scales out.
 */
export const layerStoreMemoryBounded = Layer.effect(
  RateLimiter.RateLimiterStore,
  Effect.gen(function* () {
    const inner = yield* RateLimiter.RateLimiterStore;
    const counters = new Map<string, { count: number; expiresAt: number }>();
    let nextSweep = 0;

    return RateLimiter.RateLimiterStore.of({
      ...inner,
      fixedWindow: (options) =>
        Effect.clockWith((clock) =>
          Effect.sync(() => {
            const refillRateMillis = Duration.toMillis(options.refillRate);
            const now = clock.currentTimeMillisUnsafe();
            if (now >= nextSweep) {
              nextSweep = now + SWEEP_EVERY;
              for (const [key, counter] of counters) {
                if (counter.expiresAt <= now) counters.delete(key);
              }
            }
            let counter = counters.get(options.key);
            if (!counter || counter.expiresAt <= now) {
              counter = { count: 0, expiresAt: now };
              counters.set(options.key, counter);
            }
            if (options.limit && counter.count + options.tokens > options.limit) {
              return [counter.count + options.tokens, counter.expiresAt - now] as const;
            }
            counter.count += options.tokens;
            counter.expiresAt += refillRateMillis * options.tokens;
            return [counter.count, counter.expiresAt - now] as const;
          }),
        ),
    });
  }),
).pipe(Layer.provide(RateLimiter.layerStoreMemory));
