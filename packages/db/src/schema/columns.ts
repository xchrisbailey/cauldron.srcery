import { timestamp } from "drizzle-orm/pg-core";

/**
 * A timestamptz column with millisecond precision. JavaScript `Date`s (and the
 * pagination cursors built from them) only carry milliseconds, while Postgres
 * `now()` has microseconds; a keyset comparison on a microsecond column can
 * skip or repeat rows. Use this for every timestamp column, and always for
 * columns used as keyset pagination keys.
 */
export const timestampMs = (name: string) => timestamp(name, { withTimezone: true, precision: 3 });

/** `created_at` and `updated_at`, both millisecond precision. Spread into a table's columns. */
export const timestamps = () => ({
  createdAt: timestampMs("created_at").notNull().defaultNow(),
  updatedAt: timestampMs("updated_at")
    .notNull()
    .defaultNow()
    .$onUpdate(() => new Date()),
});
