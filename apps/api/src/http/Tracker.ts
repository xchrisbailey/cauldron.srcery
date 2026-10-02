import { Api } from "@cauldron/api-spec";
import { copy, Unavailable } from "@cauldron/shared";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { RecipeExtractor } from "../imports/RecipeExtractor.ts";
import { Tracker } from "../Tracker.ts";
import { owned } from "./owned.ts";

// Thin handlers over the Tracker service, which owns the queries and owner scoping.

export const TrackerHandlers = HttpApiBuilder.group(
  Api,
  "tracker",
  Effect.fn(function* (handlers) {
    const tracker = yield* Tracker;
    const model = yield* RecipeExtractor;
    return handlers
      .handle("describe", ({ payload }) =>
        model.estimateMeal(payload.text).pipe(
          Effect.flatMap((items) =>
            items.length === 0
              ? Effect.fail(new Unavailable({ message: copy.tracker.describe.unreadable.text }))
              : Effect.succeed({ items }),
          ),
          Effect.catchTag("ExtractError", (error) =>
            error.reason === "unavailable"
              ? Effect.fail(new Unavailable({ message: copy.tracker.describe.unavailable.text }))
              : Effect.logWarning("Meal estimate failed", error).pipe(
                  Effect.andThen(
                    Effect.fail(new Unavailable({ message: copy.tracker.describe.failed.text })),
                  ),
                ),
          ),
        ),
      )
      .handle("day", ({ query }) => owned((owner) => tracker.day(owner, query.date)))
      .handle("intake", ({ query }) => owned((owner) => tracker.intake(owner, query)))
      .handle("add", ({ payload }) => owned((owner) => tracker.add(owner, payload)))
      .handle("addMany", ({ payload }) => owned((owner) => tracker.addMany(owner, payload)))
      .handle("update", ({ params, payload }) =>
        owned((owner) => tracker.update(owner, params.id, payload)),
      )
      .handle("remove", ({ params }) => owned((owner) => tracker.remove(owner, params.id)))
      .handle("settings", () => owned((owner) => tracker.settings(owner)))
      .handle("saveProfile", ({ payload }) => owned((owner) => tracker.saveProfile(owner, payload)))
      .handle("saveTargets", ({ payload }) => owned((owner) => tracker.saveTargets(owner, payload)))
      .handle("weighIns", ({ query }) => owned((owner) => tracker.weighIns(owner, query)))
      .handle("weighIn", ({ params, payload }) =>
        owned((owner) => tracker.saveWeighIn(owner, params.date, payload)),
      )
      .handle("removeWeighIn", ({ params }) =>
        owned((owner) => tracker.removeWeighIn(owner, params.date)),
      );
  }),
);
