import { copy, DEFAULT_PAGE_LIMIT, InvalidRequest, type PageQuery } from "@cauldron/shared";
import { and, lt, eq, or, type AnyColumn, type SQL } from "drizzle-orm";
import { Effect, Schema } from "effect";

// Opaque cursors: base64url of JSON `{ c: createdAt ISO, i: id }`. Clients
// must treat them as strings and pass them back unchanged.
const Cursor = Schema.Struct({ c: Schema.String, i: Schema.String });
const CursorFromString = Schema.StringFromBase64Url.pipe(
  Schema.decodeTo(Schema.fromJsonString(Cursor)),
);
const decodeCursor = Schema.decodeUnknownEffect(CursorFromString);
const encodeCursor = Schema.encodeEffect(CursorFromString);

export interface CursorPosition {
  readonly createdAt: Date;
  readonly id: string;
}

export const makeCursor = (position: CursorPosition) =>
  encodeCursor({ c: position.createdAt.toISOString(), i: position.id }).pipe(Effect.orDie);

/**
 * Decodes a cursor; anything malformed fails with the shared `InvalidRequest`.
 * `idSchema` validates the id inside the cursor (for example `Schema.String.check(Schema.isUUID())` for
 * a uuid column), so a tampered id is a 400 here and not a database error.
 */
export const parseCursor = Effect.fn("Pagination.parseCursor")(function* <I extends string>(
  cursor: string,
  idSchema: Schema.Codec<I, string>,
) {
  const invalid = () => new InvalidRequest({ message: copy.errors.invalidRequest.text });
  const decoded = yield* decodeCursor(cursor).pipe(Effect.mapError(invalid));
  const createdAt = new Date(decoded.c);
  if (Number.isNaN(createdAt.getTime())) return yield* invalid();
  const id = yield* Schema.decodeEffect(idSchema)(decoded.i).pipe(Effect.mapError(invalid));
  return { createdAt, id } as { readonly createdAt: Date; readonly id: I };
});

export interface PaginateOptions<Row extends CursorPosition, I extends string, E, R> {
  readonly query: PageQuery;
  /** The `created_at` and `id` columns of the table being listed. */
  readonly createdAt: AnyColumn;
  readonly id: AnyColumn;
  /** Validates the id carried in a cursor, for example `Schema.String.check(Schema.isUUID())`. */
  readonly idSchema: Schema.Codec<I, string>;
  /**
   * Runs the query. Add `where` (undefined on the first page) to your own
   * conditions, order by `desc(createdAt), desc(id)`, and apply `limit`.
   */
  readonly run: (page: {
    readonly where: SQL | undefined;
    readonly limit: number;
  }) => Effect.Effect<ReadonlyArray<Row>, E, R>;
}

/**
 * Keyset pagination for rows ordered by (created_at desc, id desc). Fetches
 * one extra row to know whether another page exists.
 *
 * The `createdAt` column must have millisecond precision (`timestampMs` from
 * `@cauldron/db`, i.e. `precision: 3`). Cursors carry a JavaScript `Date`, which
 * has no microseconds; against a microsecond column (Postgres `now()` default)
 * the comparison would skip or repeat rows at page boundaries.
 *
 * ```ts
 * paginate({
 *   query,
 *   createdAt: recipes.createdAt,
 *   id: recipes.id,
 *   idSchema: Schema.String.check(Schema.isUUID()),
 *   run: ({ where, limit }) =>
 *     db.use((d) =>
 *       d.select().from(recipes)
 *         .where(and(eq(recipes.ownerId, user.id), where))
 *         .orderBy(desc(recipes.createdAt), desc(recipes.id))
 *         .limit(limit),
 *     ),
 * });
 * ```
 */
export const paginate = Effect.fn("Pagination.paginate")(function* <
  Row extends CursorPosition,
  I extends string,
  E,
  R,
>(options: PaginateOptions<Row, I, E, R>) {
  const limit = options.query.limit ?? DEFAULT_PAGE_LIMIT;
  let where: SQL | undefined;
  if (options.query.cursor !== undefined) {
    const after = yield* parseCursor(options.query.cursor, options.idSchema);
    where = or(
      lt(options.createdAt, after.createdAt),
      and(eq(options.createdAt, after.createdAt), lt(options.id, after.id)),
    );
  }
  const rows = yield* options.run({ where, limit: limit + 1 });
  const items = rows.slice(0, limit);
  const last = items[items.length - 1];
  const nextCursor = rows.length > limit && last ? yield* makeCursor(last) : null;
  return { items, nextCursor };
});
