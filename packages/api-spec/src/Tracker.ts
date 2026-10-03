import {
  BodyProfile,
  DiaryBatchInput,
  DiaryDay,
  DiaryDayQuery,
  DiaryEntry,
  DiaryEntryId,
  DiaryEntryInput,
  DiaryEntryUpdate,
  IntakeDay,
  LocalDate,
  MealDescription,
  MealEstimate,
  Targets,
  TargetsInput,
  TrackerRangeQuery,
  TrackerSettings,
  WeighIn,
  WeighInInput,
} from "@cauldron/shared";
import { Schema } from "effect";
import { HttpApiEndpoint, HttpApiGroup, OpenApi } from "effect/http-api";
import { Authorization } from "./Authorization.ts";
import {
  InvalidRequestError,
  NotFoundError,
  TooManyRequestsError,
  UnavailableError,
} from "./errors.ts";
import { RateLimit, RateLimitPolicy } from "./RateLimit.ts";

const entry = { id: DiaryEntryId };
const day = { date: LocalDate };

export class TrackerApi extends HttpApiGroup.make("tracker")
  .add(
    HttpApiEndpoint.get("day", "/day", {
      query: DiaryDayQuery,
      success: DiaryDay,
    }).annotate(
      OpenApi.Description,
      "One day of the diary: its entries by slot and position, what they add up to, the daily targets and the day's weigh-in.",
    ),
    HttpApiEndpoint.get("intake", "/intake", {
      query: TrackerRangeQuery,
      success: Schema.Array(IntakeDay),
      error: InvalidRequestError,
    }).annotate(
      OpenApi.Description,
      "What each day from `from` to `to` added up to (at most 367 days). Days with nothing logged are left out.",
    ),
    HttpApiEndpoint.post("describe", "/describe", {
      payload: MealDescription,
      success: MealEstimate,
      error: [InvalidRequestError, UnavailableError, TooManyRequestsError],
    })
      .middleware(RateLimit)
      .annotate(RateLimitPolicy, { limit: 20, window: "1 minute" })
      .annotate(
        OpenApi.Description,
        "Splits a meal described in words into foods, each with an amount and estimated calories and macros, using the configured AI model. Nothing is logged. 503 when no model is set up or it can't answer.",
      ),
    HttpApiEndpoint.post("add", "/entries", {
      payload: DiaryEntryInput,
      success: DiaryEntry,
      error: InvalidRequestError,
    }).annotate(
      OpenApi.Description,
      "Logs something eaten. With `recipeId`, the recipe's title and per-serving numbers are copied unless given.",
    ),
    HttpApiEndpoint.post("addMany", "/entries/batch", {
      payload: DiaryBatchInput,
      success: Schema.Array(DiaryEntry),
      error: InvalidRequestError,
    }).annotate(OpenApi.Description, "Logs up to 100 entries, all or none, in the order sent."),
    HttpApiEndpoint.patch("update", "/entries/:id", {
      params: entry,
      payload: DiaryEntryUpdate,
      success: DiaryEntry,
      error: [NotFoundError, InvalidRequestError],
    }),
    HttpApiEndpoint.delete("remove", "/entries/:id", {
      params: entry,
      success: DiaryEntry,
      error: NotFoundError,
    }),
    HttpApiEndpoint.get("settings", "/settings", { success: TrackerSettings }).annotate(
      OpenApi.Description,
      "The body profile and daily targets; each is null until set.",
    ),
    HttpApiEndpoint.put("saveProfile", "/profile", {
      payload: BodyProfile,
      success: BodyProfile,
    }),
    HttpApiEndpoint.put("saveTargets", "/targets", {
      payload: TargetsInput,
      success: Targets,
    }),
    HttpApiEndpoint.get("weighIns", "/weigh-ins", {
      query: TrackerRangeQuery,
      success: Schema.Array(WeighIn),
      error: InvalidRequestError,
    }).annotate(OpenApi.Description, "Weigh-ins from `from` to `to`, oldest first."),
    HttpApiEndpoint.put("weighIn", "/weigh-ins/:date", {
      params: day,
      payload: WeighInInput,
      success: WeighIn,
    }).annotate(OpenApi.Description, "Logs the day's weight, replacing any already logged."),
    HttpApiEndpoint.delete("removeWeighIn", "/weigh-ins/:date", {
      params: day,
      success: WeighIn,
      error: NotFoundError,
    }),
  )
  .middleware(Authorization)
  .prefix("/tracker")
  .annotateMerge(OpenApi.annotations({ title: "Tracker" })) {}
