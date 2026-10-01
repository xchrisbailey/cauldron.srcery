import { schema } from "@cauldron/db";
import {
  addDays,
  copy,
  daysBetween,
  InvalidRequest,
  NotFound,
  PLAN_LIMITS,
  type PlanEntry,
  PlanEntryId,
  RecipeId,
  type LocalDate,
  type MealSlot,
  type PlanCopyInput,
  type PlanEntryInput,
  type PlanEntryUpdate,
  type PlanRangeQuery,
  type UserId,
} from "@cauldron/shared";
import { and, asc, between, eq, inArray, isNull, ne, sql, type SQL } from "drizzle-orm";
import { Context, Effect, Layer } from "effect";
import { Db } from "./Db.ts";

const { mealPlanEntry: entry, recipe, recipeCook } = schema;

const notFound = () => new NotFound({ message: copy.errors.notFound.text });
const invalid = () => new InvalidRequest({ message: copy.errors.invalidRequest.text });
const slotFull = () => new InvalidRequest({ message: copy.week.slotFull.text });

type Slot = { readonly date: string; readonly slot: MealSlot };

const make = Effect.gen(function* () {
  const db = yield* Db;

  /** Entries with their live recipe, by day, slot and position. */
  const select = (ownerId: UserId, where: SQL | undefined) =>
    db
      .use((d) =>
        d
          .select({
            id: entry.id,
            date: entry.date,
            slot: entry.slot,
            title: entry.title,
            servings: entry.servings,
            position: entry.position,
            recipeId: recipe.id,
            recipeTitle: recipe.title,
            recipeServings: recipe.servings,
            totalMinutes: recipe.totalMinutes,
            prepMinutes: recipe.prepMinutes,
            cookMinutes: recipe.cookMinutes,
            photoKey: recipe.photoKey,
            brewed: sql<boolean>`exists (select 1 from ${recipeCook} where ${recipeCook.recipeId} = ${entry.recipeId} and ${recipeCook.ownerId} = ${entry.ownerId} and ${recipeCook.cookedOn} = ${entry.date})`,
          })
          .from(entry)
          // A banished recipe reads as gone; the entry keeps its title.
          .leftJoin(
            recipe,
            and(
              eq(recipe.id, entry.recipeId),
              eq(recipe.ownerId, entry.ownerId),
              isNull(recipe.deletedAt),
            ),
          )
          .where(and(eq(entry.ownerId, ownerId), where))
          // The slot enum sorts in meal order: breakfast, lunch, dinner, snack.
          .orderBy(asc(entry.date), asc(entry.slot), asc(entry.position), asc(entry.createdAt)),
      )
      .pipe(
        Effect.map((rows) =>
          rows.map((row): PlanEntry => ({
            id: PlanEntryId.make(row.id),
            date: row.date,
            slot: row.slot,
            title: row.title,
            recipe:
              row.recipeId === null
                ? null
                : {
                    id: RecipeId.make(row.recipeId),
                    title: row.recipeTitle!,
                    servings: row.recipeServings,
                    totalMinutes:
                      row.totalMinutes ??
                      (row.prepMinutes !== null || row.cookMinutes !== null
                        ? (row.prepMinutes ?? 0) + (row.cookMinutes ?? 0)
                        : null),
                    photoKey: row.photoKey,
                  },
            servings: row.servings,
            position: row.position,
            brewed: row.recipeId !== null && Boolean(row.brewed),
          })),
        ),
      );

  const one = Effect.fn("Plan.one")(function* (ownerId: UserId, id: string) {
    const [found] = yield* select(ownerId, eq(entry.id, id));
    if (!found) return yield* notFound();
    return found;
  });

  const inRange = (from: string, to: string) => between(entry.date, from, to);

  const checkRange = Effect.fn("Plan.checkRange")(function* (from: string, to: string) {
    const days = daysBetween(from, to);
    if (days < 0 || days >= PLAN_LIMITS.rangeDays) return yield* invalid();
  });

  /** Serializes writes to one day's slot, so concurrent adds can't pass the limit or share a position. */
  const lockSlot = (ownerId: UserId, at: Slot) =>
    db.use((d) =>
      d.execute(
        sql`select pg_advisory_xact_lock(hashtext(${`plan/${ownerId}/${at.date}/${at.slot}`}))`,
      ),
    );

  /** Ids in a slot, in order, leaving out `except`. */
  const slotIds = (ownerId: UserId, at: Slot, except?: string) =>
    db
      .use((d) =>
        d
          .select({ id: entry.id })
          .from(entry)
          .where(
            and(
              eq(entry.ownerId, ownerId),
              eq(entry.date, at.date),
              eq(entry.slot, at.slot),
              except === undefined ? undefined : ne(entry.id, except),
            ),
          )
          .orderBy(asc(entry.position), asc(entry.createdAt)),
      )
      .pipe(Effect.map((rows) => rows.map((row) => row.id)));

  /** Writes positions 0..n in the given order. A slot holds at most a few entries. */
  const writeOrder = Effect.fn("Plan.writeOrder")(function* (
    ownerId: UserId,
    at: Slot,
    ids: ReadonlyArray<string>,
  ) {
    for (const [position, id] of ids.entries()) {
      yield* db.use((d) =>
        d
          .update(entry)
          .set({ date: at.date, slot: at.slot, position })
          .where(and(eq(entry.id, id), eq(entry.ownerId, ownerId))),
      );
    }
  });

  const list = Effect.fn("Plan.list")(function* (ownerId: UserId, query: PlanRangeQuery) {
    yield* checkRange(query.from, query.to);
    return yield* select(ownerId, inRange(query.from, query.to));
  });

  const add = Effect.fn("Plan.add")(function* (ownerId: UserId, input: PlanEntryInput) {
    const recipeId = input.recipeId ?? null;
    const text = input.title ?? null;
    // Exactly one of a recipe or free text.
    if ((recipeId === null) === (text === null)) return yield* invalid();
    return yield* db.transaction(
      Effect.gen(function* () {
        if (input.id !== undefined) {
          // A retry of an add that already landed: hand back what's there.
          const [already] = yield* db.use((d) =>
            d.select({ ownerId: entry.ownerId }).from(entry).where(eq(entry.id, input.id!)),
          );
          if (already)
            return already.ownerId === ownerId
              ? yield* one(ownerId, input.id).pipe(Effect.catchTag("NotFound", Effect.die))
              : yield* invalid();
        }
        let title = text!;
        if (recipeId !== null) {
          const [live] = yield* db.use((d) =>
            d
              .select({ title: recipe.title })
              .from(recipe)
              .where(
                and(eq(recipe.id, recipeId), eq(recipe.ownerId, ownerId), isNull(recipe.deletedAt)),
              ),
          );
          if (!live) return yield* invalid();
          title = live.title;
        }
        const at = { date: input.date, slot: input.slot };
        yield* lockSlot(ownerId, at);
        const ids = yield* slotIds(ownerId, at);
        if (ids.length >= PLAN_LIMITS.perSlot) return yield* slotFull();
        const [row] = yield* db.use((d) =>
          d
            .insert(entry)
            .values({
              ...(input.id === undefined ? {} : { id: input.id }),
              ownerId,
              date: input.date,
              slot: input.slot,
              recipeId,
              title,
              servings: input.servings ?? null,
              position: ids.length,
            })
            .returning({ id: entry.id }),
        );
        const position = Math.min(input.position ?? ids.length, ids.length);
        if (position < ids.length) {
          yield* writeOrder(ownerId, at, ids.toSpliced(position, 0, row!.id));
        }
        // Just inserted in this transaction, so it's there.
        return yield* one(ownerId, row!.id).pipe(Effect.catchTag("NotFound", Effect.die));
      }),
    );
  });

  const update = Effect.fn("Plan.update")(function* (
    ownerId: UserId,
    id: PlanEntryId,
    input: PlanEntryUpdate,
  ) {
    return yield* db.transaction(
      Effect.gen(function* () {
        const [row] = yield* db.use((d) =>
          d
            .select()
            .from(entry)
            .where(and(eq(entry.id, id), eq(entry.ownerId, ownerId)))
            .for("update"),
        );
        if (!row) return yield* notFound();
        // Only free text can be renamed; a recipe entry follows its recipe. An
        // entry whose recipe is banished reads as free text, so it can be renamed.
        if (input.title !== undefined && row.recipeId !== null) {
          const [live] = yield* db.use((d) =>
            d
              .select({ id: recipe.id })
              .from(recipe)
              .where(
                and(
                  eq(recipe.id, row.recipeId!),
                  eq(recipe.ownerId, ownerId),
                  isNull(recipe.deletedAt),
                ),
              ),
          );
          if (live) return yield* invalid();
        }
        if (input.servings !== undefined || input.title !== undefined) {
          yield* db.use((d) =>
            d
              .update(entry)
              .set({
                ...(input.servings === undefined ? {} : { servings: input.servings }),
                ...(input.title === undefined ? {} : { title: input.title }),
              })
              .where(and(eq(entry.id, id), eq(entry.ownerId, ownerId))),
          );
        }
        if (input.date !== undefined || input.slot !== undefined || input.position !== undefined) {
          const from: Slot = { date: row.date, slot: row.slot };
          const to: Slot = { date: input.date ?? row.date, slot: input.slot ?? row.slot };
          const moved = from.date !== to.date || from.slot !== to.slot;
          yield* lockSlot(ownerId, to);
          const siblings = yield* slotIds(ownerId, to, id);
          if (moved && siblings.length >= PLAN_LIMITS.perSlot) return yield* slotFull();
          const current = moved ? siblings.length : (yield* slotIds(ownerId, from)).indexOf(id);
          const position = Math.min(input.position ?? current, siblings.length);
          yield* writeOrder(ownerId, to, siblings.toSpliced(position, 0, id));
          if (moved) yield* writeOrder(ownerId, from, yield* slotIds(ownerId, from, id));
        }
        return yield* one(ownerId, id);
      }),
    );
  });

  const remove = Effect.fn("Plan.remove")(function* (ownerId: UserId, id: PlanEntryId) {
    return yield* db.transaction(
      Effect.gen(function* () {
        const removed = yield* one(ownerId, id);
        yield* db.use((d) =>
          d.delete(entry).where(and(eq(entry.id, id), eq(entry.ownerId, ownerId))),
        );
        // Gaps would sort fine, but keep positions dense for clients that index by them.
        const at = { date: removed.date, slot: removed.slot };
        yield* writeOrder(ownerId, at, yield* slotIds(ownerId, at));
        return removed;
      }),
    );
  });

  const copyWeek = Effect.fn("Plan.copyWeek")(function* (ownerId: UserId, input: PlanCopyInput) {
    const shift = daysBetween(input.from, input.to);
    if (shift === 0) return yield* invalid();
    const target = { from: input.to, to: addDays(input.to, 6) };
    return yield* db.transaction(
      Effect.gen(function* () {
        const source = yield* db.use((d) =>
          d
            .select()
            .from(entry)
            .where(and(eq(entry.ownerId, ownerId), inRange(input.from, addDays(input.from, 6))))
            .orderBy(asc(entry.date), asc(entry.slot), asc(entry.position), asc(entry.createdAt)),
        );
        if (source.length > 0) {
          // Copies go after whatever the target slots already hold, up to the slot limit.
          const existing = yield* db.use((d) =>
            d
              .select({ date: entry.date, slot: entry.slot, n: sql<number>`count(*)::int` })
              .from(entry)
              .where(and(eq(entry.ownerId, ownerId), inRange(target.from, target.to)))
              .groupBy(entry.date, entry.slot),
          );
          const next = new Map(existing.map((row) => [`${row.date}/${row.slot}`, Number(row.n)]));
          const values: Array<typeof entry.$inferInsert> = [];
          for (const row of source) {
            const date = addDays(row.date, shift) as LocalDate;
            const key = `${date}/${row.slot}`;
            const position = next.get(key) ?? 0;
            if (position >= PLAN_LIMITS.perSlot) continue;
            next.set(key, position + 1);
            values.push({
              ownerId,
              date,
              slot: row.slot,
              recipeId: row.recipeId,
              title: row.title,
              servings: row.servings,
              position,
            });
          }
          if (values.length > 0) yield* db.use((d) => d.insert(entry).values(values));
        }
        return yield* select(ownerId, inRange(target.from, target.to));
      }),
    );
  });

  const clear = Effect.fn("Plan.clear")(function* (ownerId: UserId, query: PlanRangeQuery) {
    yield* checkRange(query.from, query.to);
    return yield* db.transaction(
      Effect.gen(function* () {
        const removed = yield* select(ownerId, inRange(query.from, query.to));
        if (removed.length > 0) {
          yield* db.use((d) =>
            d.delete(entry).where(
              and(
                eq(entry.ownerId, ownerId),
                inArray(
                  entry.id,
                  removed.map((e) => e.id),
                ),
              ),
            ),
          );
        }
        return removed;
      }),
    );
  });

  return { list, add, update, remove, copy: copyWeek, clear };
});

/** The week: meal plan entries, every read and write scoped to one owner. */
export class Plan extends Context.Service<Plan, Effect.Success<typeof make>>()(
  "cauldron/api/Plan",
) {
  static readonly layer = Layer.effect(Plan, make);
}
