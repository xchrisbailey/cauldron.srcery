import { Api } from "@cauldron/api-spec";
import { copy, Unavailable } from "@cauldron/shared";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { RecipeExtractor } from "../imports/RecipeExtractor.ts";
import { Recipes } from "../Recipes.ts";
import { owned } from "./owned.ts";

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
      .handle("list", ({ query }) => owned((owner) => recipes.list(owner, query)))
      .handle("search", ({ query }) => owned((owner) => recipes.search(owner, query)))
      .handle("get", ({ params }) => owned((owner) => recipes.get(owner, params.id)))
      .handle("create", ({ payload }) => owned((owner) => recipes.create(owner, payload)))
      .handle("update", ({ params, payload }) =>
        owned((owner) => recipes.update(owner, params.id, payload)),
      )
      .handle("banish", ({ params }) => owned((owner) => recipes.banish(owner, params.id)))
      .handle("restore", ({ params }) => owned((owner) => recipes.restore(owner, params.id)))
      .handle("duplicate", ({ params }) => owned((owner) => recipes.duplicate(owner, params.id)))
      .handle("cooked", ({ params, payload }) =>
        owned((owner) => recipes.cooked(owner, params.id, payload.on)),
      );
  }),
);

export const TagsHandlers = HttpApiBuilder.group(
  Api,
  "tags",
  Effect.fn(function* (handlers) {
    const recipes = yield* Recipes;
    return handlers
      .handle("list", () => owned((owner) => recipes.tags(owner)))
      .handle("rename", ({ params, payload }) =>
        owned((owner) => recipes.renameTag(owner, params.id, payload)),
      );
  }),
);
