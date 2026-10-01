import { Api, CurrentUser } from "@cauldron/api-spec";
import { copy, Unavailable } from "@cauldron/shared";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { RecipeExtractor } from "../imports/RecipeExtractor.ts";
import { Recipes } from "../Recipes.ts";

// Thin handlers: the Recipes service owns the queries and the owner scoping.
// A DbError here is a bug or an outage, so it becomes a defect, which the
// error shape turns into a logged, redacted 500.

export const RecipesHandlers = HttpApiBuilder.group(
  Api,
  "recipes",
  Effect.fn(function* (handlers) {
    const recipes = yield* Recipes;
    const model = yield* RecipeExtractor;
    return handlers
      .handle("estimateMacros", ({ payload }) =>
        model
          .estimateMacros(payload)
          .pipe(
            Effect.catchTag("ExtractError", (error) =>
              error.reason === "unavailable"
                ? Effect.fail(new Unavailable({ message: copy.editor.divineUnavailable.text }))
                : Effect.logWarning("Macro estimate failed", error).pipe(
                    Effect.andThen(
                      Effect.fail(new Unavailable({ message: copy.editor.divineFailed.text })),
                    ),
                  ),
            ),
          ),
      )
      .handle("list", ({ query }) =>
        CurrentUser.use((user) => recipes.list(user.id, query)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("search", ({ query }) =>
        CurrentUser.use((user) => recipes.search(user.id, query)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("get", ({ params }) =>
        CurrentUser.use((user) => recipes.get(user.id, params.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("create", ({ payload }) =>
        CurrentUser.use((user) => recipes.create(user.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("update", ({ params, payload }) =>
        CurrentUser.use((user) => recipes.update(user.id, params.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("banish", ({ params }) =>
        CurrentUser.use((user) => recipes.banish(user.id, params.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("restore", ({ params }) =>
        CurrentUser.use((user) => recipes.restore(user.id, params.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("duplicate", ({ params }) =>
        CurrentUser.use((user) => recipes.duplicate(user.id, params.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("cooked", ({ params, payload }) =>
        CurrentUser.use((user) => recipes.cooked(user.id, params.id, payload.on)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      );
  }),
);

export const TagsHandlers = HttpApiBuilder.group(
  Api,
  "tags",
  Effect.fn(function* (handlers) {
    const recipes = yield* Recipes;
    return handlers
      .handle("list", () =>
        CurrentUser.use((user) => recipes.tags(user.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("rename", ({ params, payload }) =>
        CurrentUser.use((user) => recipes.renameTag(user.id, params.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      );
  }),
);
