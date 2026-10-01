import { Api } from "@cauldron/api-spec";
import { Cause, Effect, Option } from "effect";
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

// Rejects with the typed error itself (a domain error, or a transport error),
// or the squashed defect; read it with `failureOf` (api-failure.ts).
export const callApi = async <A, E>(
  f: (client: HttpApiClient.ForApi<typeof Api>) => Effect.Effect<A, E>,
): Promise<A> => {
  const exit = await Effect.gen(function* () {
    const client = yield* HttpApiClient.make(Api, { baseUrl: baseUrl() });
    return yield* f(client);
  }).pipe(Effect.provide(FetchHttpClient.layer), Effect.runPromiseExit);
  if (exit._tag === "Success") return exit.value;
  const typed = Cause.findErrorOption(exit.cause);
  throw Option.isSome(typed) ? typed.value : Cause.squash(exit.cause);
};
