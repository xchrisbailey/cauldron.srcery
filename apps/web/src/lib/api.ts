import { Api } from "@cauldron/api-spec";
import { Effect } from "effect";
import { FetchHttpClient } from "effect/http";
import { HttpApiClient } from "effect/http-api";

// The one place the web app runs Effect: turning typed client calls into
// promises for TanStack Query. Components never touch the runtime.
const baseUrl = () =>
  typeof window === "undefined" ? "http://localhost:3000" : window.location.origin;

export const callApi = <A, E>(
  f: (client: HttpApiClient.ForApi<typeof Api>) => Effect.Effect<A, E>,
) =>
  Effect.gen(function* () {
    const client = yield* HttpApiClient.make(Api, { baseUrl: baseUrl() });
    return yield* f(client);
  }).pipe(Effect.provide(FetchHttpClient.layer), Effect.runPromise);
