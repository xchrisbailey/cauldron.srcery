import { QueryClient } from "@tanstack/react-query";
import { createRouter } from "@tanstack/react-router";
import { createIsomorphicFn } from "@tanstack/react-start";
import { getRequestHeader } from "@tanstack/react-start/server";
import { RouteError } from "./components/RouteError";
import { retryWhile } from "./lib/api-failure";
import { routeTree } from "./routeTree.gen";

// The CSP nonce server.ts sets per request (always overwriting a client-sent
// one). Only the server reads it; in the browser the router picks it up from
// the csp-nonce meta tag it rendered.
const requestSsr = createIsomorphicFn()
  .server(() => {
    const nonce = getRequestHeader("x-csp-nonce");
    return nonce ? { nonce } : {};
  })
  .client(() => ({}));

export function getRouter() {
  const queryClient = new QueryClient({
    defaultOptions: {
      // A missing recipe or a signed-out visitor fails at once instead of
      // retrying; a dropped connection still gets a few tries.
      queries: { staleTime: 30_000, retry: retryWhile(3) },
    },
  });
  return createRouter({
    routeTree,
    context: { queryClient },
    scrollRestoration: true,
    defaultPreload: "intent",
    // TanStack Query decides when data is fresh, so the router never caches loader results.
    defaultPreloadStaleTime: 0,
    defaultErrorComponent: RouteError,
    // Gives Start's inline hydration scripts and the theme script the nonce the CSP allows.
    ssr: requestSsr(),
  });
}

declare module "@tanstack/react-router" {
  interface Register {
    router: ReturnType<typeof getRouter>;
  }
}
