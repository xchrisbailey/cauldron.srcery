import { queryOptions } from "@tanstack/react-query";
import { callApi } from "./api";

/** Which sign-in providers the API has configured, and whether it takes new accounts. */
export const signInOptionsQuery = queryOptions({
  queryKey: ["sign-in-options"],
  queryFn: () => callApi((c) => c.signInOptions()),
  staleTime: Infinity,
});

/** The `?error=` code a provider sign-in comes back with when it would have created an account. */
export const SIGN_UP_CLOSED = "SIGN_UP_CLOSED";
