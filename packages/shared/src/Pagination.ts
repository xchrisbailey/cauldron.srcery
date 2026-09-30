import { Schema } from "effect";

export const DEFAULT_PAGE_LIMIT = 20;
export const MAX_PAGE_LIMIT = 100;

/**
 * Query string for cursor-paginated list routes. `limit` arrives as a string
 * and is decoded to an integer between 1 and 100; the server applies
 * `DEFAULT_PAGE_LIMIT` when it is absent.
 */
export const PageQuery = Schema.Struct({
  cursor: Schema.optionalKey(Schema.String),
  limit: Schema.optionalKey(
    Schema.NumberFromString.check(
      Schema.isInt(),
      Schema.isBetween({ minimum: 1, maximum: MAX_PAGE_LIMIT }),
    ),
  ),
});
export type PageQuery = typeof PageQuery.Type;

/** One page of a list. `nextCursor` is null on the last page. */
export const Page = <S extends Schema.Top>(item: S) =>
  Schema.Struct({
    items: Schema.Array(item),
    nextCursor: Schema.NullOr(Schema.String),
  });
