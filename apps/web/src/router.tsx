import { QueryClient } from "@tanstack/react-query";
import { createRouter } from "@tanstack/react-router";
import { RouteError } from "./components/RouteError";
import { retryWhile } from "./lib/api-failure";
import { routeTree } from "./routeTree.gen";

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
  });
}

declare module "@tanstack/react-router" {
  interface Register {
    router: ReturnType<typeof getRouter>;
  }
}
