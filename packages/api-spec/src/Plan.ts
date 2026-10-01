import {
  PlanCopyInput,
  PlanEntry,
  PlanEntryId,
  PlanEntryInput,
  PlanEntryUpdate,
  PlanRangeQuery,
} from "@cauldron/shared";
import { Schema } from "effect";
import { HttpApiEndpoint, HttpApiGroup, OpenApi } from "effect/http-api";
import { Authorization } from "./Authorization.ts";
import { InvalidRequestError, NotFoundError } from "./errors.ts";

const params = { id: PlanEntryId };

export class PlanApi extends HttpApiGroup.make("plan")
  .add(
    HttpApiEndpoint.get("list", "/", {
      query: PlanRangeQuery,
      success: Schema.Array(PlanEntry),
      error: InvalidRequestError,
    }).annotate(
      OpenApi.Description,
      "Entries from `from` to `to` (both included, at most 62 days), by day, slot and position.",
    ),
    HttpApiEndpoint.post("add", "/", {
      payload: PlanEntryInput,
      success: PlanEntry,
      error: InvalidRequestError,
    }).annotate(
      OpenApi.Description,
      "Stirs a recipe into a meal slot (`recipeId`), or adds a free-text meal (`title`).",
    ),
    HttpApiEndpoint.patch("update", "/:id", {
      params,
      payload: PlanEntryUpdate,
      success: PlanEntry,
      error: [NotFoundError, InvalidRequestError],
    }).annotate(
      OpenApi.Description,
      "Moves an entry to another day, slot or position, changes its servings, or renames free text.",
    ),
    HttpApiEndpoint.delete("remove", "/:id", {
      params,
      success: PlanEntry,
      error: NotFoundError,
    }),
    HttpApiEndpoint.post("copy", "/copy", {
      payload: PlanCopyInput,
      success: Schema.Array(PlanEntry),
      error: InvalidRequestError,
    }).annotate(
      OpenApi.Description,
      "Adds a copy of every entry in the seven days from `from` to the seven days from `to`, and returns the target week.",
    ),
    HttpApiEndpoint.post("clear", "/clear", {
      payload: PlanRangeQuery,
      success: Schema.Array(PlanEntry),
      error: InvalidRequestError,
    }).annotate(OpenApi.Description, "Removes every entry in the range and returns them."),
  )
  .middleware(Authorization)
  .prefix("/plan")
  .annotateMerge(OpenApi.annotations({ title: "The week" })) {}
