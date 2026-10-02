import type { QueryClient } from "@tanstack/react-query";
import { type ParsedLocation, redirect } from "@tanstack/react-router";
import { sessionQuery } from "./session";

/**
 * A route guard for signed-in pages: anyone else is sent to sign in and
 * brought back afterwards. A failed verification link lands signed out with
 * `error` set; that goes to sign-in, which offers a new link, instead of
 * bouncing back here after.
 */
export async function requireSignIn({
  location,
  context,
}: {
  location: ParsedLocation;
  context: { queryClient: QueryClient };
}) {
  const session = await context.queryClient.fetchQuery(sessionQuery);
  const error = (location.search as { error?: string }).error;
  if (!session && error) throw redirect({ to: "/sign-in", search: { error } });
  if (!session) throw redirect({ to: "/sign-in", search: { redirect: location.href } });
  return { session };
}
