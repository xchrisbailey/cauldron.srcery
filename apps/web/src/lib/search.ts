import { Schema } from "effect";

/** A presence flag in the URL (`?verified=1`). The router parses search values as JSON, so accept any scalar. */
export const SearchFlag = Schema.optional(
  Schema.Union([Schema.String, Schema.Finite, Schema.Boolean]),
);
