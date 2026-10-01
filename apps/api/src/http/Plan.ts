import { Api } from "@cauldron/api-spec";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { Plan } from "../Plan.ts";
import { owned } from "./owned.ts";

// Thin handlers over the Plan service, which owns the queries and owner scoping.

export const PlanHandlers = HttpApiBuilder.group(
  Api,
  "plan",
  Effect.fn(function* (handlers) {
    const plan = yield* Plan;
    return handlers
      .handle("list", ({ query }) => owned((owner) => plan.list(owner, query)))
      .handle("add", ({ payload }) => owned((owner) => plan.add(owner, payload)))
      .handle("addMany", ({ payload }) => owned((owner) => plan.addMany(owner, payload)))
      .handle("update", ({ params, payload }) =>
        owned((owner) => plan.update(owner, params.id, payload)),
      )
      .handle("remove", ({ params }) => owned((owner) => plan.remove(owner, params.id)))
      .handle("copy", ({ payload }) => owned((owner) => plan.copy(owner, payload)))
      .handle("clear", ({ payload }) => owned((owner) => plan.clear(owner, payload)));
  }),
);
