import { Api } from "@cauldron/api-spec";
import { Effect } from "effect";
import { HttpApiBuilder } from "effect/http-api";
import { Gather } from "../Gather.ts";
import { owned } from "./owned.ts";

// Thin handlers over the Gather service, which owns the queries and owner scoping.

export const GatherHandlers = HttpApiBuilder.group(
  Api,
  "gather",
  Effect.fn(function* (handlers) {
    const gather = yield* Gather;
    return handlers
      .handle("week", ({ params }) => owned((owner) => gather.week(owner, params.weekStart)))
      .handle("add", ({ params, payload }) =>
        owned((owner) => gather.add(owner, params.weekStart, payload)),
      )
      .handle("update", ({ params, payload }) =>
        owned((owner) => gather.update(owner, params.id, payload)),
      )
      .handle("remove", ({ params }) => owned((owner) => gather.remove(owner, params.id)));
  }),
);
