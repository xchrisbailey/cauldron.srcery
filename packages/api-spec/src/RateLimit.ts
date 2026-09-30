import { Context, type Duration } from "effect";
import { HttpApiMiddleware } from "effect/http-api";
import { TooManyRequestsError } from "./errors.ts";

export interface RateLimitPolicyValue {
  readonly limit: number;
  readonly window: Duration.Input;
}

/** Per-endpoint policy, set with `.annotate(RateLimitPolicy, { limit, window })`. Defaults to 30 per minute. */
export const RateLimitPolicy = Context.Reference<RateLimitPolicyValue>(
  "cauldron/api-spec/RateLimitPolicy",
  { defaultValue: () => ({ limit: 30, window: "1 minute" }) },
);

// Opt in with `.middleware(RateLimit)` on expensive endpoints (AI extraction,
// URL import, search). The server implementation lives in apps/api.
export class RateLimit extends HttpApiMiddleware.Service<RateLimit>()(
  "cauldron/api-spec/RateLimit",
  { error: TooManyRequestsError },
) {}
