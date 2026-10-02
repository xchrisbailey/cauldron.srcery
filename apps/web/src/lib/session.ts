import { queryOptions } from "@tanstack/react-query";
import { createServerFn } from "@tanstack/react-start";
import { getRequestHeaders, setResponseHeader } from "@tanstack/react-start/server";

export interface Session {
  readonly user: { readonly id: string; readonly name: string; readonly email: string };
}

const apiOrigin = () => process.env.API_ORIGIN ?? "http://localhost:3001";

// Runs on the web server for SSR and client navigations alike, forwarding the
// visitor's cookie to the API, so route guards see the same session either way.
export const getSession = createServerFn({ method: "GET" }).handler(
  async (): Promise<Session | null> => {
    // The answer is per visitor; never let a shared cache keep it.
    setResponseHeader("cache-control", "private, no-store");
    const cookie = getRequestHeaders().get("cookie");
    if (!cookie) return null;
    const res = await fetch(`${apiOrigin()}/v1/auth/get-session`, { headers: { cookie } });
    // A refreshed session comes back as Set-Cookie; hand it to the browser so the cookie renews.
    const setCookies = res.headers.getSetCookie();
    if (setCookies.length > 0) setResponseHeader("set-cookie", setCookies);
    if (!res.ok) return null;
    const body = (await res.json()) as Session | null;
    return body?.user
      ? { user: { id: body.user.id, name: body.user.name, email: body.user.email } }
      : null;
  },
);

/**
 * The session for route guards, through the query cache. Guards run on every
 * navigation and every intent preload, so a signed-in session is reused for a
 * minute instead of asking the API each time. Signed out is never kept, so
 * signing in is seen at once; signing out clears the cache (account.tsx).
 */
export const sessionQuery = queryOptions({
  queryKey: ["session"],
  queryFn: () => getSession(),
  staleTime: (query) => (query.state.data ? 60_000 : 0),
  // Every page waits on this; with the API down, fail now rather than after backoff.
  retry: false,
});
