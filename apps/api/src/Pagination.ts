import { copy, DEFAULT_PAGE_LIMIT, InvalidRequest, type PageQuery } from "@cauldron/shared";
import { and, desc, eq, lt, or, type SQL } from "drizzle-orm";
import type { PgColumn } from "drizzle-orm/pg-core";
import { Effect, Schema } from "effect";

/**
 * One way to order a list for keyset pagination. Every order ends on the row
 * id, so ties on the key break the same way on every page.
 */
export interface SortKey<Row> {
  /** Carried in the cursor, so a cursor from another sort is rejected. */
  readonly name: string;
  /** The row's position in this order, as the string the cursor carries. */
  readonly key: (row: Row) => string;
  /** Whether a key from a cursor has the shape `after` compares in SQL. */
  readonly valid: (key: string) => boolean;
  /** The ORDER BY for this sort, ending on the id. */
  readonly orderBy: ReadonlyArray<PgColumn | SQL>;
  /** Rows strictly after the row at (`key`, `id`) in this order. */
  readonly after: (key: string, id: string) => SQL;
}

/**
 * The built-in sort: newest first, by (created_at desc, id desc).
 *
 * The `createdAt` column must have millisecond precision (`timestampMs` from
 * `@cauldron/db`, i.e. `precision: 3`). Cursors carry a JavaScript `Date`, which
 * has no microseconds; against a microsecond column (Postgres `now()` default)
 * the comparison would skip or repeat rows at page boundaries.
 */
export const newestFirst = <Row extends { readonly createdAt: Date }>(
  columns: { readonly createdAt: PgColumn; readonly id: PgColumn },
  name = "recent",
): SortKey<Row> => ({
  name,
  key: (row) => row.createdAt.toISOString(),
  valid: (key) => {
    const date = new Date(key);
    return !Number.isNaN(date.getTime()) && date.toISOString() === key;
  },
  orderBy: [desc(columns.createdAt), desc(columns.id)],
  after: (key, id) => {
    const at = new Date(key);
    return or(lt(columns.createdAt, at), and(eq(columns.createdAt, at), lt(columns.id, id))) as SQL;
  },
});

// Opaque cursors: base64url of JSON `{ s: sort name, k: sort key, i: id }`.
// Clients must treat them as strings and pass them back unchanged.
const Cursor = Schema.Struct({ s: Schema.String, k: Schema.String, i: Schema.String });
const CursorFromString = Schema.StringFromBase64Url.pipe(
  Schema.decodeTo(Schema.fromJsonString(Cursor)),
);
const decodeCursor = Schema.decodeUnknownEffect(CursorFromString);
const encodeCursor = Schema.encodeEffect(CursorFromString);

/** The cursor that continues `sort` after `row`. */
export const makeCursor = <Row extends { readonly id: string }>(sort: SortKey<Row>, row: Row) =>
  encodeCursor({ s: sort.name, k: sort.key(row), i: row.id }).pipe(Effect.orDie);

const invalid = () => new InvalidRequest({ message: copy.errors.invalidRequest.text });

/**
 * Decodes a cursor for `sort` into the condition for the rows after it. A
 * malformed cursor, one from another sort, a key `sort` can't compare, or an
 * id `idSchema` rejects all fail with the shared `InvalidRequest`, so a
 * tampered cursor is a 400 here and not a database error.
 */
const parseCursor = Effect.fn("Pagination.parseCursor")(function* <Row>(
  cursor: string,
  sort: SortKey<Row>,
  idSchema: Schema.Codec<string, string>,
) {
  const decoded = yield* decodeCursor(cursor).pipe(Effect.mapError(invalid));
  if (decoded.s !== sort.name || !sort.valid(decoded.k)) return yield* invalid();
  const id = yield* Schema.decodeEffect(idSchema)(decoded.i).pipe(Effect.mapError(invalid));
  return sort.after(decoded.k, id);
});

export interface PaginateOptions<Row extends { readonly id: string }, E, R> {
  readonly query: PageQuery;
  readonly sort: SortKey<Row>;
  /** Validates the id carried in a cursor, for example `Schema.String.check(Schema.isUUID())`. */
  readonly idSchema: Schema.Codec<string, string>;
  /**
   * Runs the query. Add `where` (undefined on the first page) to your own
   * conditions, order by `orderBy`, and apply `limit`.
   */
  readonly run: (page: {
    readonly where: SQL | undefined;
    readonly orderBy: ReadonlyArray<PgColumn | SQL>;
    readonly limit: number;
  }) => Effect.Effect<ReadonlyArray<Row>, E, R>;
}

/**
 * Keyset pagination in the order of `sort`. Fetches one extra row to know
 * whether another page exists.
 *
 * ```ts
 * paginate({
 *   query,
 *   sort: newestFirst(recipes),
 *   idSchema: Schema.String.check(Schema.isUUID()),
 *   run: ({ where, orderBy, limit }) =>
 *     db.use((d) =>
 *       d.select().from(recipes)
 *         .where(and(eq(recipes.ownerId, user.id), where))
 *         .orderBy(...orderBy)
 *         .limit(limit),
 *     ),
 * });
 * ```
 */
export const paginate = Effect.fn("Pagination.paginate")(function* <
  Row extends { readonly id: string },
  E,
  R,
>(options: PaginateOptions<Row, E, R>) {
  const limit = options.query.limit ?? DEFAULT_PAGE_LIMIT;
  const where =
    options.query.cursor === undefined
      ? undefined
      : yield* parseCursor(options.query.cursor, options.sort, options.idSchema);
  const rows = yield* options.run({ where, orderBy: options.sort.orderBy, limit: limit + 1 });
  const items = rows.slice(0, limit);
  const last = items[items.length - 1];
  const nextCursor = rows.length > limit && last ? yield* makeCursor(options.sort, last) : null;
  return { items, nextCursor };
});
