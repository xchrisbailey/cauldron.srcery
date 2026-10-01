import { Api, CurrentUser } from "@cauldron/api-spec";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { Imports } from "../Imports.ts";

// A DbError here is a bug or an outage: a defect, logged as a 500.
export const ImportsHandlers = HttpApiBuilder.group(
  Api,
  "imports",
  Effect.fn(function* (handlers) {
    const imports = yield* Imports;
    return handlers
      .handle("start", ({ payload }) =>
        CurrentUser.use((user) => imports.start(user.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("get", ({ params }) =>
        CurrentUser.use((user) => imports.get(user.id, params.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("cancel", ({ params }) =>
        CurrentUser.use((user) => imports.cancel(user.id, params.id)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      )
      .handle("save", ({ params, payload }) =>
        CurrentUser.use((user) => imports.save(user.id, params.id, payload)).pipe(
          Effect.catchTag("DbError", Effect.die),
        ),
      );
  }),
);
