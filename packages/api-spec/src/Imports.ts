import { ImportId, ImportInput, ImportJob, Recipe, RecipeInput } from "@cauldron/shared";
import { HttpApiEndpoint, HttpApiGroup, OpenApi } from "effect/http-api";
import { Authorization } from "./Authorization.ts";
import {
  ConflictError,
  InvalidRequestError,
  NotFoundError,
  TooManyRequestsError,
} from "./errors.ts";
import { RateLimit, RateLimitPolicy } from "./RateLimit.ts";

const params = { id: ImportId };

// Distill (#13): imports run as background jobs. Start one, poll it until it's
// done, then save the reviewed draft as a recipe.
export class ImportsApi extends HttpApiGroup.make("imports")
  .add(
    HttpApiEndpoint.post("start", "/", {
      payload: ImportInput,
      success: ImportJob,
      error: [InvalidRequestError, TooManyRequestsError],
    })
      .middleware(RateLimit)
      .annotate(RateLimitPolicy, { limit: 20, window: "1 minute" })
      .annotate(
        OpenApi.Description,
        "Starts distilling a link or pasted text. Poll the job until it's done or failed.",
      ),
    HttpApiEndpoint.get("get", "/:id", { params, success: ImportJob, error: NotFoundError }),
    HttpApiEndpoint.delete("cancel", "/:id", {
      params,
      success: ImportJob,
      error: NotFoundError,
    }).annotate(
      OpenApi.Description,
      "Stops a job that hasn't finished. Finished jobs are left as they are.",
    ),
    HttpApiEndpoint.post("save", "/:id/recipe", {
      params,
      payload: RecipeInput,
      success: Recipe,
      error: [NotFoundError, InvalidRequestError, ConflictError],
    }).annotate(
      OpenApi.Description,
      "Saves the reviewed draft as a recipe, recording where it came from.",
    ),
  )
  .middleware(Authorization)
  .prefix("/imports")
  .annotateMerge(OpenApi.annotations({ title: "Imports" })) {}
