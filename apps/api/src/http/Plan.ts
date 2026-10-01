import { Api, CurrentUser } from "@cauldron/api-spec";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { Plan } from "../Plan.ts";

// Thin handlers over the Plan service, which owns the queries and owner scoping.

export const PlanHandlers = HttpApiBuilder.group(
  Api,
  "plan",
  Effect.fn(function* (handlers) {
    const plan = yield* Plan;
    return handlers
      .handle("list", ({ query }) =>
        CurrentUser.use((user) => plan.list(user.id, query)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("add", ({ payload }) =>
        CurrentUser.use((user) => plan.add(user.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("update", ({ params, payload }) =>
        CurrentUser.use((user) => plan.update(user.id, params.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("remove", ({ params }) =>
        CurrentUser.use((user) => plan.remove(user.id, params.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("copy", ({ payload }) =>
        CurrentUser.use((user) => plan.copy(user.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("clear", ({ payload }) =>
        CurrentUser.use((user) => plan.clear(user.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      );
  }),
);
