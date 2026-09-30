import { Api, CurrentUser, Health } from "@cauldron/api-spec";
import { Effect, Layer } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { AuthorizationLive } from "./Authorization.ts";

const SystemHandlers = HttpApiBuilder.group(Api, "system", (handlers) =>
  Effect.succeed(handlers.handle("health", () => Effect.succeed(new Health({ status: "ok" })))),
);

const AccountHandlers = HttpApiBuilder.group(Api, "account", (handlers) =>
  Effect.succeed(handlers.handle("me", () => CurrentUser)),
);

export const ApiRoutes = HttpApiBuilder.layer(Api, { openapiPath: "/v1/openapi.json" }).pipe(
  Layer.provide([SystemHandlers, AccountHandlers]),
  Layer.provide(AuthorizationLive),
);
