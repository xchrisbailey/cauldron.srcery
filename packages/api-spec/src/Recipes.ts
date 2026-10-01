import {
  CookedInput,
  Page,
  Recipe,
  RecipeId,
  RecipeInput,
  RecipeListQuery,
  RecipeSearchQuery,
  RecipeSummary,
  TagId,
  TagUpdate,
  TagWithCount,
} from "@cauldron/shared";
import { Schema } from "effect";
import { HttpApiEndpoint, HttpApiGroup, OpenApi } from "effect/http-api";
import { Authorization } from "./Authorization.ts";
import { ConflictError, InvalidRequestError, NotFoundError } from "./errors.ts";
import { RateLimit, RateLimitPolicy } from "./RateLimit.ts";

const params = { id: RecipeId };

export class RecipesApi extends HttpApiGroup.make("recipes")
  .add(
    HttpApiEndpoint.get("list", "/", {
      query: RecipeListQuery,
      success: Page(RecipeSummary),
      error: InvalidRequestError,
    }).annotate(OpenApi.Description, "Live recipes, newest first by default, a page at a time."),
    HttpApiEndpoint.get("search", "/search", {
      query: RecipeSearchQuery,
      success: Schema.Array(RecipeSummary),
    })
      .middleware(RateLimit)
      .annotate(RateLimitPolicy, { limit: 240, window: "1 minute" })
      .annotate(
        OpenApi.Description,
        "Best matches by title, tag and ingredient, for search-as-you-type.",
      ),
    HttpApiEndpoint.get("get", "/:id", { params, success: Recipe, error: NotFoundError }),
    HttpApiEndpoint.post("create", "/", { payload: RecipeInput, success: Recipe }),
    HttpApiEndpoint.put("update", "/:id", {
      params,
      payload: RecipeInput,
      success: Recipe,
      error: NotFoundError,
    }).annotate(OpenApi.Description, "Replaces the whole recipe, ingredients and steps included."),
    HttpApiEndpoint.delete("banish", "/:id", {
      params,
      success: Recipe,
      error: NotFoundError,
    }).annotate(OpenApi.Description, "Soft deletes a recipe. Restore brings it back."),
    HttpApiEndpoint.post("restore", "/:id/restore", {
      params,
      success: Recipe,
      error: NotFoundError,
    }),
    HttpApiEndpoint.post("duplicate", "/:id/duplicate", {
      params,
      success: Recipe,
      error: NotFoundError,
    }),
    HttpApiEndpoint.post("cooked", "/:id/cooked", {
      params,
      payload: CookedInput,
      success: Recipe,
      error: NotFoundError,
    }).annotate(OpenApi.Description, "Records the day a recipe was cooked."),
  )
  .middleware(Authorization)
  .prefix("/recipes")
  .annotateMerge(OpenApi.annotations({ title: "Recipes" })) {}

export class TagsApi extends HttpApiGroup.make("tags")
  .add(
    HttpApiEndpoint.get("list", "/", { success: Schema.Array(TagWithCount) }),
    HttpApiEndpoint.patch("rename", "/:id", {
      params: { id: TagId },
      payload: TagUpdate,
      success: TagWithCount,
      error: [NotFoundError, ConflictError],
    }),
  )
  .middleware(Authorization)
  .prefix("/tags")
  .annotateMerge(OpenApi.annotations({ title: "Tags" })) {}
