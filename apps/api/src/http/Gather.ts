import { Api, CurrentUser } from "@cauldron/api-spec";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { Gather } from "../Gather.ts";

// Thin handlers over the Gather service, which owns the queries and owner scoping.

export const GatherHandlers = HttpApiBuilder.group(
  Api,
  "gather",
  Effect.fn(function* (handlers) {
    const gather = yield* Gather;
    return handlers
      .handle("week", ({ params }) =>
        CurrentUser.use((user) => gather.week(user.id, params.weekStart)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("add", ({ params, payload }) =>
        CurrentUser.use((user) => gather.add(user.id, params.weekStart, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("update", ({ params, payload }) =>
        CurrentUser.use((user) => gather.update(user.id, params.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("remove", ({ params }) =>
        CurrentUser.use((user) => gather.remove(user.id, params.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      );
  }),
);
