import { Api } from "@cauldron/api-spec";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { Imports } from "../Imports.ts";
import { owned } from "./owned.ts";

// A DbError here is a bug or an outage: a defect, logged as a 500.
export const ImportsHandlers = HttpApiBuilder.group(
  Api,
  "imports",
  Effect.fn(function* (handlers) {
    const imports = yield* Imports;
    return handlers
      .handle("start", ({ payload }) => owned((owner) => imports.start(owner, payload)))
      .handle("get", ({ params }) => owned((owner) => imports.get(owner, params.id)))
      .handle("cancel", ({ params }) => owned((owner) => imports.cancel(owner, params.id)))
      .handle("save", ({ params, payload }) =>
        owned((owner) => imports.save(owner, params.id, payload)),
      );
  }),
);
