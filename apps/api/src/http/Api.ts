import { Api, CurrentUser, Health, SignInOptions, Version } from "@cauldron/api-spec";
import { copy, Unavailable } from "@cauldron/shared";
import { Effect, Layer } from "effect";
import { HttpApiBuilder, HttpApiScalar } from "effect/http-api";
import { AppConfig } from "../AppConfig.ts";
import { Db, redactDbError } from "../Db.ts";
import { AuthorizationLive } from "./Authorization.ts";
import { Recipes } from "../Recipes.ts";
import { RecipesHandlers, TagsHandlers } from "./Recipes.ts";

const SystemHandlers = HttpApiBuilder.group(
  Api,
  "system",
  Effect.fn(function* (handlers) {
    const db = yield* Db;
    const config = yield* AppConfig;
    return handlers
      .handle("health", () =>
        db.ping.pipe(
          Effect.as(new Health({ status: "ok", database: "ok" })),
          Effect.catchTag("DbError", (error) =>
            Effect.logWarning("Health check failed", redactDbError(error)).pipe(
              Effect.andThen(new Unavailable({ message: copy.errors.unavailable.text })),
            ),
          ),
        ),
      )
      .handle("version", () =>
        Effect.succeed(new Version({ version: config.version, commit: config.commit ?? null })),
      )
      .handle("signInOptions", () =>
        Effect.succeed(
          new SignInOptions({
            google: config.social.google !== undefined,
            apple: config.social.apple !== undefined,
            dev: config.devOAuth !== undefined,
          }),
        ),
      );
  }),
);

const AccountHandlers = HttpApiBuilder.group(Api, "account", (handlers) =>
  Effect.succeed(handlers.handle("me", () => CurrentUser)),
);

const Docs = Layer.unwrap(
  Effect.gen(function* () {
    const config = yield* AppConfig;
    return config.docs ? HttpApiScalar.layer(Api, { path: "/v1/docs" }) : Layer.empty;
  }),
);

export const ApiRoutes = Layer.mergeAll(
  HttpApiBuilder.layer(Api, { openapiPath: "/v1/openapi.json" }).pipe(
    Layer.provide([SystemHandlers, AccountHandlers, RecipesHandlers, TagsHandlers]),
    Layer.provide([AuthorizationLive, Recipes.layer]),
  ),
  Docs,
);
