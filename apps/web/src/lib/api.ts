import { Api } from "@cauldron/api-spec";
import { Effect } from "effect";
import { FetchHttpClient } from "effect/http";
import { HttpApiClient } from "effect/http-api";

// The one place the web app runs Effect: turning typed client calls into
// promises for TanStack Query. Components never touch the runtime.
//
// In the browser it calls the same origin (the /v1 proxy). During SSR it calls
// the API directly without the visitor's cookie, so signed-in data is fetched
// on the client or through a server function that forwards the cookie
// (see session.ts).
const baseUrl = () =>
  typeof window === "undefined"
    ? (process.env.API_ORIGIN ?? "http://localhost:3001")
    : window.location.origin;

export const callApi = <A, E>(
  f: (client: HttpApiClient.ForApi<typeof Api>) => Effect.Effect<A, E>,
) =>
  Effect.gen(function* () {
    const client = yield* HttpApiClient.make(Api, { baseUrl: baseUrl() });
    return yield* f(client);
  }).pipe(Effect.provide(FetchHttpClient.layer), Effect.runPromise);
