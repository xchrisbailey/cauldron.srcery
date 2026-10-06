import { copy } from "@cauldron/shared";

/**
 * Message for a failed password-reset request. Rate limits get their own wording; everything
 * else is the generic one. Nothing here depends on whether the account exists.
 */
export const resetRequestErrorMessage = (error: unknown): string => {
  const tooMany =
    typeof error === "object" &&
    error !== null &&
    (("status" in error && error.status === 429) ||
      ("code" in error && error.code === "TOO_MANY_REQUESTS"));
  return tooMany ? copy.errors.tooManyRequests.text : copy.errors.internal.text;
};
