import { ingredient, macros, refreshRecipeSearch, schema } from "@cauldron/db";
import {
  Conflict,
  copy,
  DEFAULT_PAGE_LIMIT,
  InvalidRequest,
  isRealDate,
  NotFound,
  Recipe,
  RECIPE_LIMITS,
  RecipeId,
  RecipeSummary,
  Tag,
  TagId,
  TagWithCount,
  type LocalDate,
  type RecipeInput,
  type RecipeListQuery,
  type RecipeSearchQuery,
  type RecipeSort,
  type Step,
  type TagUpdate,
  type UserId,
} from "@cauldron/shared";
import {
  and,
  asc,
  count,
  desc,
  eq,
  getTableColumns,
  inArray,
  isNotNull,
  isNull,
  sql,
  type SQL,
} from "drizzle-orm";
import { Context, Effect, Layer, Schema } from "effect";
import { Db, isUniqueViolation } from "./Db.ts";

const { photo, recipe, recipeCook, recipeIngredient, recipeStep, recipeTag, tag } = schema;

// Every recipe column but the search document, which only SQL reads.
const { search: _search, ...recipeColumns } = getTableColumns(recipe);
type RecipeRow = Omit<typeof recipe.$inferSelect, "search">;
/** A listed row with the title's sort key, lowercased by Postgres so the cursor matches the comparison. */
type ListedRow = RecipeRow & { readonly titleKey: string };
type StepRow = typeof recipeStep.$inferSelect;

const notFound = () => new NotFound({ message: copy.errors.notFound.text });
const invalid = () => new InvalidRequest({ message: copy.errors.invalidRequest.text });

/** Blank optional text is stored as null. */
const orNull = (value: string | null): string | null =>
  value === null || value === "" ? null : value;

// ---------------------------------------------------------------------------
// Rows to domain

const toStep = (row: StepRow): Step => ({
  section: row.section,
  text: row.text,
  timerSeconds: row.timerSeconds,
});

const toTag = (row: { id: string; name: string; kind: Tag["kind"] }) =>
  new Tag({ id: TagId.make(row.id), name: row.name, kind: row.kind });

const summaryFields = (row: RecipeRow, tags: ReadonlyArray<Tag>) => ({
  id: RecipeId.make(row.id),
  title: row.title,
  description: row.description,
  servings: row.servings,
  prepMinutes: row.prepMinutes,
  cookMinutes: row.cookMinutes,
  totalMinutes: row.totalMinutes,
  photoKey: row.photoKey,
  macros: macros.fromRow(row),
  tags,
  lastCookedOn: row.lastCookedOn,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
});

// ---------------------------------------------------------------------------
// Search

/**
 * Turns what someone typed into a prefix tsquery: every word must match the
 * start of a word in the title, tags, ingredients or description. Only letters
 * and digits survive, so the result is always valid tsquery syntax.
 */
export const toPrefixQuery = (q: string): string | null => {
  const words =
    q
      .toLowerCase()
      .match(/[\p{L}\p{N}]+/gu)
      ?.slice(0, 8) ?? [];
  return words.length === 0 ? null : words.map((word) => `${word}:*`).join(" & ");
};

const likePattern = (q: string) => `%${q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;

/** Matches by full text (with prefixes) or a plain substring of the title. */
const searchCondition = (q: string): SQL | undefined => {
  const prefix = toPrefixQuery(q);
  if (prefix === null) return undefined;
  return sql`(${recipe.search} @@ to_tsquery('english', ${prefix}) or ${recipe.title} ilike ${likePattern(q)})`;
};

// ---------------------------------------------------------------------------
// Keyset cursors for the three sorts

const Cursor = Schema.Struct({
  s: Schema.Literals(["recent", "title", "lastCooked"]),
  k: Schema.String,
  i: Schema.String.check(Schema.isUUID()),
});
const CursorFromString = Schema.StringFromBase64Url.pipe(
  Schema.decodeTo(Schema.fromJsonString(Cursor)),
);

/** For sorting by last cooked: never-cooked recipes sort after every real date. */
const NEVER_COOKED = "0001-01-01";

const sortKey = (sort: RecipeSort) => {
  switch (sort) {
    case "recent":
      return {
        key: (row: ListedRow) => row.createdAt.toISOString(),
        orderBy: [desc(recipe.createdAt), desc(recipe.id)],
        after: (k: string, id: string) =>
          sql`(${recipe.createdAt} < ${k}::timestamptz or (${recipe.createdAt} = ${k}::timestamptz and ${recipe.id} < ${id}))`,
      };
    case "title":
      return {
        key: (row: ListedRow) => row.titleKey,
        orderBy: [asc(sql`lower(${recipe.title})`), asc(recipe.id)],
        after: (k: string, id: string) =>
          sql`(lower(${recipe.title}) > ${k} or (lower(${recipe.title}) = ${k} and ${recipe.id} > ${id}))`,
      };
    case "lastCooked": {
      // The same expression as recipe_owner_cooked_idx, so the index serves it.
      const cooked = sql`coalesce(${recipe.lastCookedOn}, '0001-01-01'::date)`;
      return {
        key: (row: ListedRow) => row.lastCookedOn ?? NEVER_COOKED,
        orderBy: [desc(cooked), desc(recipe.id)],
        after: (k: string, id: string) =>
          sql`(${cooked} < ${k}::date or (${cooked} = ${k}::date and ${recipe.id} < ${id}))`,
      };
    }
  }
};

// The cursor's key is compared in SQL, so check it has the right shape first.
const validKey = (sort: RecipeSort, k: string) => {
  switch (sort) {
    case "recent": {
      const date = new Date(k);
      return !Number.isNaN(date.getTime()) && date.toISOString() === k;
    }
    case "title":
      return k.length <= RECIPE_LIMITS.title * 2;
    case "lastCooked":
      return isRealDate(k);
  }
};

// ---------------------------------------------------------------------------

const make = Effect.gen(function* () {
  const db = yield* Db;

  const tagsFor = Effect.fn("Recipes.tagsFor")(function* (
    ownerId: string,
    recipeIds: ReadonlyArray<string>,
  ) {
    const byRecipe = new Map<string, Array<Tag>>();
    if (recipeIds.length === 0) return byRecipe;
    const rows = yield* db.use((d) =>
      d
        .select({ recipeId: recipeTag.recipeId, id: tag.id, name: tag.name, kind: tag.kind })
        .from(recipeTag)
        .innerJoin(tag, eq(tag.id, recipeTag.tagId))
        .where(and(eq(recipeTag.ownerId, ownerId), inArray(recipeTag.recipeId, [...recipeIds])))
        .orderBy(asc(sql`lower(${tag.name})`)),
    );
    for (const row of rows) {
      const list = byRecipe.get(row.recipeId) ?? [];
      list.push(toTag(row));
      byRecipe.set(row.recipeId, list);
    }
    return byRecipe;
  });

  const summaries = Effect.fn("Recipes.summaries")(function* (
    ownerId: UserId,
    rows: ReadonlyArray<RecipeRow>,
  ) {
    const tags = yield* tagsFor(
      ownerId,
      rows.map((row) => row.id),
    );
    return rows.map((row) => new RecipeSummary(summaryFields(row, tags.get(row.id) ?? [])));
  });

  const findRow = Effect.fn("Recipes.findRow")(function* (
    ownerId: UserId,
    id: RecipeId,
    deleted: "live" | "any" = "live",
  ) {
    const rows = yield* db.use((d) =>
      d
        .select(recipeColumns)
        .from(recipe)
        .where(
          and(
            eq(recipe.id, id),
            eq(recipe.ownerId, ownerId),
            deleted === "live" ? isNull(recipe.deletedAt) : undefined,
          ),
        )
        .limit(1),
    );
    const row = rows[0];
    if (!row) return yield* notFound();
    return row;
  });

  const load = Effect.fn("Recipes.load")(function* (row: RecipeRow) {
    const [ingredients, steps, tags] = yield* Effect.all([
      db.use((d) =>
        d
          .select()
          .from(recipeIngredient)
          .where(
            and(eq(recipeIngredient.ownerId, row.ownerId), eq(recipeIngredient.recipeId, row.id)),
          )
          .orderBy(asc(recipeIngredient.position)),
      ),
      db.use((d) =>
        d
          .select()
          .from(recipeStep)
          .where(and(eq(recipeStep.ownerId, row.ownerId), eq(recipeStep.recipeId, row.id)))
          .orderBy(asc(recipeStep.position)),
      ),
      tagsFor(row.ownerId, [row.id]),
    ]);
    return new Recipe({
      ...summaryFields(row, tags.get(row.id) ?? []),
      sourcePlatform: row.sourcePlatform,
      sourceUrl: row.sourceUrl,
      sourceAuthor: row.sourceAuthor,
      notes: row.notes,
      ingredients: ingredients.map(ingredient.fromRow),
      steps: steps.map(toStep),
      deletedAt: row.deletedAt,
    });
  });

  /** Finds or creates the owner's tags by name (case-insensitively) and returns their ids. */
  const ensureTags = Effect.fn("Recipes.ensureTags")(function* (
    ownerId: UserId,
    names: ReadonlyArray<string>,
  ) {
    const unique = new Map<string, string>();
    for (const name of names) {
      if (!unique.has(name.toLowerCase())) unique.set(name.toLowerCase(), name);
    }
    if (unique.size === 0) return [];
    yield* db.use((d) =>
      d
        .insert(tag)
        .values([...unique.values()].map((name) => ({ ownerId, name })))
        .onConflictDoNothing(),
    );
    const rows = yield* db.use((d) =>
      d
        .select({ id: tag.id })
        .from(tag)
        .where(and(eq(tag.ownerId, ownerId), inArray(sql`lower(${tag.name})`, [...unique.keys()]))),
    );
    return rows.map((row) => row.id);
  });

  /** Replaces a recipe's ingredients, steps and tags, then refreshes its search document. */
  const writeChildren = Effect.fn("Recipes.writeChildren")(function* (
    ownerId: UserId,
    recipeId: string,
    input: Pick<RecipeInput, "ingredients" | "steps" | "tags">,
  ) {
    yield* db.use((d) =>
      d
        .delete(recipeIngredient)
        .where(and(eq(recipeIngredient.ownerId, ownerId), eq(recipeIngredient.recipeId, recipeId))),
    );
    yield* db.use((d) =>
      d
        .delete(recipeStep)
        .where(and(eq(recipeStep.ownerId, ownerId), eq(recipeStep.recipeId, recipeId))),
    );
    yield* db.use((d) =>
      d
        .delete(recipeTag)
        .where(and(eq(recipeTag.ownerId, ownerId), eq(recipeTag.recipeId, recipeId))),
    );
    if (input.ingredients.length > 0) {
      yield* db.use((d) =>
        d.insert(recipeIngredient).values(
          input.ingredients.map((line, position) => ({
            ownerId,
            recipeId,
            position,
            ...ingredient.toRow(line),
          })),
        ),
      );
    }
    if (input.steps.length > 0) {
      yield* db.use((d) =>
        d.insert(recipeStep).values(
          input.steps.map((step, position) => ({
            ownerId,
            recipeId,
            position,
            section: orNull(step.section),
            text: step.text,
            timerSeconds: step.timerSeconds,
          })),
        ),
      );
    }
    const tagIds = yield* ensureTags(ownerId, input.tags);
    if (tagIds.length > 0) {
      yield* db.use((d) =>
        d.insert(recipeTag).values(tagIds.map((tagId) => ({ ownerId, recipeId, tagId }))),
      );
    }
    yield* db.use((d) => d.execute(refreshRecipeSearch(ownerId, [recipeId])));
  });

  /** A recipe may only point at one of its owner's photos. */
  const checkPhoto = Effect.fn("Recipes.checkPhoto")(function* (
    ownerId: UserId,
    photoKey: string | null | undefined,
  ) {
    if (photoKey === null || photoKey === undefined) return;
    const rows = yield* db.use((d) =>
      d
        .select({ id: photo.id })
        .from(photo)
        .where(and(eq(photo.id, photoKey), eq(photo.ownerId, ownerId))),
    );
    if (rows.length === 0) return yield* invalid();
  });

  const fields = (input: RecipeInput) => ({
    photoKey: input.photoKey ?? null,
    title: input.title,
    description: orNull(input.description),
    servings: input.servings,
    prepMinutes: input.prepMinutes,
    cookMinutes: input.cookMinutes,
    totalMinutes: input.totalMinutes,
    sourcePlatform: input.sourcePlatform,
    sourceUrl: input.sourceUrl,
    sourceAuthor: orNull(input.sourceAuthor),
    notes: orNull(input.notes),
    // Left out, an update keeps the recipe's macros.
    ...(input.macros === undefined ? {} : macros.toRow(input.macros)),
  });

  const list = Effect.fn("Recipes.list")(function* (ownerId: UserId, query: RecipeListQuery) {
    const sort = query.sort ?? "recent";
    const order = sortKey(sort);
    const limit = query.limit ?? DEFAULT_PAGE_LIMIT;
    let after: SQL | undefined;
    if (query.cursor !== undefined) {
      const cursor = yield* Schema.decodeEffect(CursorFromString)(query.cursor).pipe(
        Effect.mapError(invalid),
      );
      if (cursor.s !== sort || !validKey(sort, cursor.k)) return yield* invalid();
      after = order.after(cursor.k, cursor.i);
    }
    const rows = yield* db.use((d) =>
      d
        .select({ ...recipeColumns, titleKey: sql<string>`lower(${recipe.title})` })
        .from(recipe)
        .where(
          and(
            eq(recipe.ownerId, ownerId),
            isNull(recipe.deletedAt),
            query.tag === undefined
              ? undefined
              : sql`exists (select 1 from ${recipeTag} where ${recipeTag.recipeId} = ${recipe.id} and ${recipeTag.tagId} = ${query.tag})`,
            query.q === undefined ? undefined : searchCondition(query.q),
            after,
          ),
        )
        .orderBy(...order.orderBy)
        .limit(limit + 1),
    );
    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    const nextCursor =
      rows.length > limit && last
        ? yield* Schema.encodeEffect(CursorFromString)({
            s: sort,
            k: order.key(last),
            i: last.id,
          }).pipe(Effect.orDie)
        : null;
    return { items: yield* summaries(ownerId, page), nextCursor };
  });

  const search = Effect.fn("Recipes.search")(function* (ownerId: UserId, query: RecipeSearchQuery) {
    const prefix = toPrefixQuery(query.q);
    const condition = searchCondition(query.q);
    if (prefix === null || condition === undefined) return [];
    const tsquery = sql`to_tsquery('english', ${prefix})`;
    const rows = yield* db.use((d) =>
      d
        .select(recipeColumns)
        .from(recipe)
        .where(and(eq(recipe.ownerId, ownerId), isNull(recipe.deletedAt), condition))
        .orderBy(
          // A title that starts with the query first, then by rank.
          desc(sql`${recipe.title} ilike ${`${query.q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`}`),
          desc(sql`ts_rank(coalesce(${recipe.search}, ''::tsvector), ${tsquery})`),
          asc(sql`lower(${recipe.title})`),
        )
        .limit(query.limit ?? 10),
    );
    return yield* summaries(ownerId, rows);
  });

  const get = Effect.fn("Recipes.get")(function* (ownerId: UserId, id: RecipeId) {
    return yield* load(yield* findRow(ownerId, id));
  });

  const create = Effect.fn("Recipes.create")(function* (ownerId: UserId, input: RecipeInput) {
    yield* checkPhoto(ownerId, input.photoKey);
    return yield* db.transaction(
      Effect.gen(function* () {
        const [row] = yield* db.use((d) =>
          d
            .insert(recipe)
            .values({ ownerId, ...fields(input) })
            .returning({ id: recipe.id }),
        );
        yield* writeChildren(ownerId, row!.id, input);
        // Just inserted in this transaction, so it's there.
        const created = yield* findRow(ownerId, RecipeId.make(row!.id)).pipe(
          Effect.catchTag("NotFound", Effect.die),
        );
        return yield* load(created);
      }),
    );
  });

  const update = Effect.fn("Recipes.update")(function* (
    ownerId: UserId,
    id: RecipeId,
    input: RecipeInput,
  ) {
    yield* checkPhoto(ownerId, input.photoKey);
    return yield* db.transaction(
      Effect.gen(function* () {
        const rows = yield* db.use((d) =>
          d
            .update(recipe)
            .set(fields(input))
            .where(and(eq(recipe.id, id), eq(recipe.ownerId, ownerId), isNull(recipe.deletedAt)))
            .returning({ id: recipe.id }),
        );
        if (rows.length === 0) return yield* notFound();
        yield* writeChildren(ownerId, id, input);
        return yield* load(yield* findRow(ownerId, id));
      }),
    );
  });

  const banish = Effect.fn("Recipes.banish")(function* (ownerId: UserId, id: RecipeId) {
    const rows = yield* db.use((d) =>
      d
        .update(recipe)
        .set({ deletedAt: new Date() })
        .where(and(eq(recipe.id, id), eq(recipe.ownerId, ownerId), isNull(recipe.deletedAt)))
        .returning(recipeColumns),
    );
    if (!rows[0]) return yield* notFound();
    return yield* load(rows[0]);
  });

  const restore = Effect.fn("Recipes.restore")(function* (ownerId: UserId, id: RecipeId) {
    const rows = yield* db.use((d) =>
      d
        .update(recipe)
        .set({ deletedAt: null })
        .where(and(eq(recipe.id, id), eq(recipe.ownerId, ownerId), isNotNull(recipe.deletedAt)))
        .returning(recipeColumns),
    );
    // Restoring a recipe that isn't banished is a no-op.
    return yield* load(rows[0] ?? (yield* findRow(ownerId, id)));
  });

  const duplicate = Effect.fn("Recipes.duplicate")(function* (ownerId: UserId, id: RecipeId) {
    return yield* db.transaction(
      Effect.gen(function* () {
        const sourceRow = yield* findRow(ownerId, id);
        const source = yield* load(sourceRow);
        // Everything but identity, history and the search document, which
        // writeChildren recomputes.
        const {
          id: _id,
          createdAt: _createdAt,
          updatedAt: _updatedAt,
          deletedAt: _deletedAt,
          lastCookedOn: _lastCookedOn,
          ...copied
        } = sourceRow;
        const [row] = yield* db.use((d) =>
          d
            .insert(recipe)
            .values({
              ...copied,
              title: copy.recipes.copyOf(source.title).text.slice(0, RECIPE_LIMITS.title),
            })
            .returning({ id: recipe.id }),
        );
        yield* writeChildren(ownerId, row!.id, {
          ingredients: source.ingredients,
          steps: source.steps,
          tags: source.tags.map((t) => t.name),
        });
        return yield* load(yield* findRow(ownerId, RecipeId.make(row!.id)));
      }),
    );
  });

  const cooked = Effect.fn("Recipes.cooked")(function* (
    ownerId: UserId,
    id: RecipeId,
    on: LocalDate,
  ) {
    return yield* db.transaction(
      Effect.gen(function* () {
        yield* findRow(ownerId, id);
        // Cooking it twice on one day is one entry.
        yield* db.use((d) =>
          d
            .insert(recipeCook)
            .values({ ownerId, recipeId: id, cookedOn: on })
            .onConflictDoNothing(),
        );
        const [row] = yield* db.use((d) =>
          d
            .update(recipe)
            .set({
              lastCookedOn: sql`greatest(${recipe.lastCookedOn}, ${on}::date)`,
            })
            .where(and(eq(recipe.id, id), eq(recipe.ownerId, ownerId)))
            .returning(recipeColumns),
        );
        return yield* load(row!);
      }),
    );
  });

  const tagCounts = (ownerId: UserId, where?: SQL) =>
    db.use((d) =>
      d
        .select({
          id: tag.id,
          name: tag.name,
          kind: tag.kind,
          recipeCount: count(recipe.id),
        })
        .from(tag)
        .leftJoin(recipeTag, eq(recipeTag.tagId, tag.id))
        .leftJoin(recipe, and(eq(recipe.id, recipeTag.recipeId), isNull(recipe.deletedAt)))
        .where(and(eq(tag.ownerId, ownerId), where))
        .groupBy(tag.id)
        .orderBy(asc(sql`lower(${tag.name})`)),
    );

  const toTagWithCount = (row: {
    id: string;
    name: string;
    kind: Tag["kind"];
    recipeCount: number;
  }) =>
    new TagWithCount({
      id: TagId.make(row.id),
      name: row.name,
      kind: row.kind,
      recipeCount: Number(row.recipeCount),
    });

  const tags = Effect.fn("Recipes.tags")(function* (ownerId: UserId) {
    return (yield* tagCounts(ownerId)).map(toTagWithCount);
  });

  const renameTag = Effect.fn("Recipes.renameTag")(function* (
    ownerId: UserId,
    id: TagId,
    update: TagUpdate,
  ) {
    return yield* db.transaction(
      Effect.gen(function* () {
        const rows = yield* db
          .use((d) =>
            d
              .update(tag)
              .set({ name: update.name })
              .where(and(eq(tag.id, id), eq(tag.ownerId, ownerId)))
              .returning({ id: tag.id }),
          )
          .pipe(
            Effect.catchIf(isUniqueViolation, () =>
              Effect.fail(new Conflict({ message: copy.recipes.tagNameTaken.text })),
            ),
          );
        if (rows.length === 0) return yield* notFound();
        const tagged = yield* db.use((d) =>
          d
            .select({ id: recipeTag.recipeId })
            .from(recipeTag)
            .where(and(eq(recipeTag.ownerId, ownerId), eq(recipeTag.tagId, id))),
        );
        if (tagged.length > 0) {
          yield* db.use((d) =>
            d.execute(
              refreshRecipeSearch(
                ownerId,
                tagged.map((row) => row.id),
              ),
            ),
          );
        }
        const [row] = yield* tagCounts(ownerId, eq(tag.id, id));
        return toTagWithCount(row!);
      }),
    );
  });

  return {
    list,
    search,
    get,
    create,
    update,
    banish,
    restore,
    duplicate,
    cooked,
    tags,
    renameTag,
  };
});

/** The recipe box: every read and write is scoped to one owner. */
export class Recipes extends Context.Service<Recipes, Effect.Success<typeof make>>()(
  "cauldron/api/Recipes",
) {
  static readonly layer = Layer.effect(Recipes, make);
}
