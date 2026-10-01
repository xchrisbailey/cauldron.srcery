import { quantity, schema } from "@cauldron/db";
import {
  addDays,
  aisleFor,
  copy,
  type GatherItem,
  GatherItemId,
  type GatherItemInput,
  type GatherItemUpdate,
  gatherWeek,
  type GatheredRow,
  ingredientKey,
  InvalidRequest,
  NotFound,
  parseIngredientLine,
  type PlannedEntry,
  RecipeId,
  reconcile,
  sortRows,
  type UserId,
} from "@cauldron/shared";
import { and, asc, between, eq, inArray, isNotNull, sql } from "drizzle-orm";
import { Context, Effect, Layer } from "effect";
import { Db } from "./Db.ts";
import { liveRecipe } from "./Recipes.ts";

const { gatherItem, gatherItemSource, mealPlanEntry, pantryItem, recipe, recipeIngredient } =
  schema;

const notFound = () => new NotFound({ message: copy.errors.notFound.text });
const invalid = () => new InvalidRequest({ message: copy.errors.invalidRequest.text });

const make = Effect.gen(function* () {
  const db = yield* Db;

  /** The week's planned recipes, each with its servings and ingredients. */
  const plannedEntries = Effect.fn("Gather.plannedEntries")(function* (
    ownerId: UserId,
    weekStart: string,
  ) {
    const entries = yield* db.use((d) =>
      d
        .select({
          recipeId: recipe.id,
          servings: mealPlanEntry.servings,
          recipeServings: recipe.servings,
        })
        .from(mealPlanEntry)
        // Banished recipes drop out of the list along with the week.
        .innerJoin(
          recipe,
          and(eq(recipe.id, mealPlanEntry.recipeId), liveRecipe(mealPlanEntry.ownerId)),
        )
        .where(
          and(
            eq(mealPlanEntry.ownerId, ownerId),
            between(mealPlanEntry.date, weekStart, addDays(weekStart, 6)),
            isNotNull(mealPlanEntry.recipeId),
          ),
        ),
    );
    const recipeIds = [...new Set(entries.map((e) => e.recipeId))];
    if (recipeIds.length === 0) return { entries: [], recipeCount: 0 };
    const ingredients = yield* db.use((d) =>
      d
        .select({
          recipeId: recipeIngredient.recipeId,
          item: recipeIngredient.item,
          itemKey: recipeIngredient.itemKey,
          quantityMin: recipeIngredient.quantityMin,
          quantityMax: recipeIngredient.quantityMax,
          unit: recipeIngredient.unit,
        })
        .from(recipeIngredient)
        .where(
          and(eq(recipeIngredient.ownerId, ownerId), inArray(recipeIngredient.recipeId, recipeIds)),
        )
        .orderBy(asc(recipeIngredient.recipeId), asc(recipeIngredient.position)),
    );
    const byRecipe = Map.groupBy(ingredients, (i) => i.recipeId);
    return {
      entries: entries.map((entry): PlannedEntry => ({
        ...entry,
        ingredients: (byRecipe.get(entry.recipeId) ?? []).map((i) => ({
          item: i.item,
          itemKey: i.itemKey,
          quantity: quantity.fromRow(i),
          unit: i.unit,
        })),
      })),
      recipeCount: recipeIds.length,
    };
  });

  const writeSources = (ownerId: UserId, gatherItemId: string, row: GatheredRow) =>
    row.sources.length === 0
      ? Effect.void
      : db
          .use((d) =>
            d.insert(gatherItemSource).values(
              row.sources.map((s) => ({
                ownerId,
                gatherItemId,
                recipeId: s.recipeId,
                unit: s.unit,
                ...quantity.toRow(s.quantity),
              })),
            ),
          )
          .pipe(Effect.asVoid);

  /**
   * Brings the gathered rows in line with the week's plan (see `reconcile`).
   * Items added by hand are never touched. A lock per owner and week keeps two
   * syncs apart.
   */
  const sync = Effect.fn("Gather.sync")(function* (ownerId: UserId, weekStart: string) {
    return yield* db.transaction(
      Effect.gen(function* () {
        yield* db.use((d) =>
          d.execute(
            sql`select pg_advisory_xact_lock(hashtext(${`gather/${ownerId}/${weekStart}`}))`,
          ),
        );
        const { entries, recipeCount } = yield* plannedEntries(ownerId, weekStart);
        const existing = yield* db.use((d) =>
          d
            .select()
            .from(gatherItem)
            .where(
              and(
                eq(gatherItem.ownerId, ownerId),
                eq(gatherItem.weekStart, weekStart),
                eq(gatherItem.manual, false),
              ),
            ),
        );
        const existingSources =
          existing.length === 0
            ? []
            : yield* db.use((d) =>
                d
                  .select()
                  .from(gatherItemSource)
                  .where(
                    and(
                      eq(gatherItemSource.ownerId, ownerId),
                      inArray(
                        gatherItemSource.gatherItemId,
                        existing.map((e) => e.id),
                      ),
                    ),
                  ),
              );
        const sourcesOf = Map.groupBy(existingSources, (s) => s.gatherItemId);
        const { inserts, updates, removals } = reconcile(
          existing.map((row) => ({
            id: row.id,
            item: row.item,
            itemKey: row.itemKey,
            quantity: quantity.fromRow(row),
            unit: row.unit,
            aisle: row.aisle,
            checked: row.checked,
            sources: (sourcesOf.get(row.id) ?? []).map((s) => ({
              recipeId: s.recipeId,
              quantity: quantity.fromRow(s),
              unit: s.unit,
            })),
          })),
          gatherWeek(entries),
          quantity.round,
        );

        for (const row of inserts) {
          const [inserted] = yield* db.use((d) =>
            d
              .insert(gatherItem)
              .values({
                ownerId,
                weekStart,
                item: row.item,
                itemKey: row.itemKey,
                unit: row.unit,
                aisle: row.aisle,
                ...quantity.toRow(row.quantity),
              })
              .returning({ id: gatherItem.id }),
          );
          yield* writeSources(ownerId, inserted!.id, row);
        }
        for (const { id, row, changed, uncheck, sources } of updates) {
          if (changed || uncheck) {
            yield* db.use((d) =>
              d
                .update(gatherItem)
                .set({
                  item: row.item,
                  unit: row.unit,
                  aisle: row.aisle,
                  ...quantity.toRow(row.quantity),
                  ...(uncheck ? { checked: false } : {}),
                })
                .where(eq(gatherItem.id, id)),
            );
          }
          if (sources) {
            yield* db.use((d) =>
              d.delete(gatherItemSource).where(eq(gatherItemSource.gatherItemId, id)),
            );
            yield* writeSources(ownerId, id, row);
          }
        }
        if (removals.length > 0) {
          yield* db.use((d) =>
            d
              .delete(gatherItem)
              .where(and(eq(gatherItem.ownerId, ownerId), inArray(gatherItem.id, removals))),
          );
        }
        return recipeCount;
      }),
    );
  });

  /** Items with their sources and pantry marks, in store order. */
  const read = Effect.fn("Gather.read")(function* (ownerId: UserId, where: ReturnType<typeof eq>) {
    const rows = yield* db.use((d) =>
      d
        .select({
          id: gatherItem.id,
          item: gatherItem.item,
          itemKey: gatherItem.itemKey,
          quantityMin: gatherItem.quantityMin,
          quantityMax: gatherItem.quantityMax,
          unit: gatherItem.unit,
          aisle: gatherItem.aisle,
          checked: gatherItem.checked,
          manual: gatherItem.manual,
          inPantry: sql<boolean>`${pantryItem.itemKey} is not null`,
        })
        .from(gatherItem)
        .leftJoin(
          pantryItem,
          and(
            eq(pantryItem.ownerId, gatherItem.ownerId),
            eq(pantryItem.itemKey, gatherItem.itemKey),
          ),
        )
        .where(and(eq(gatherItem.ownerId, ownerId), where)),
    );
    const sources =
      rows.length === 0
        ? []
        : yield* db.use((d) =>
            d
              .select({
                gatherItemId: gatherItemSource.gatherItemId,
                recipeId: gatherItemSource.recipeId,
                title: recipe.title,
                quantityMin: gatherItemSource.quantityMin,
                quantityMax: gatherItemSource.quantityMax,
                unit: gatherItemSource.unit,
              })
              .from(gatherItemSource)
              .innerJoin(
                recipe,
                and(
                  eq(recipe.id, gatherItemSource.recipeId),
                  eq(recipe.ownerId, gatherItemSource.ownerId),
                ),
              )
              .where(
                and(
                  eq(gatherItemSource.ownerId, ownerId),
                  inArray(
                    gatherItemSource.gatherItemId,
                    rows.map((r) => r.id),
                  ),
                ),
              )
              .orderBy(asc(sql`lower(${recipe.title})`)),
          );
    const sourcesOf = Map.groupBy(sources, (s) => s.gatherItemId);
    const items = rows.map((row): GatherItem => ({
      id: GatherItemId.make(row.id),
      item: row.item,
      itemKey: row.itemKey,
      quantity: quantity.fromRow(row),
      unit: row.unit,
      aisle: row.aisle ?? aisleFor(row.itemKey),
      checked: row.checked,
      manual: row.manual,
      inPantry: Boolean(row.inPantry),
      sources: (sourcesOf.get(row.id) ?? []).map((s) => ({
        recipeId: RecipeId.make(s.recipeId),
        title: s.title,
        quantity: quantity.fromRow(s),
        unit: s.unit,
      })),
    }));
    return sortRows(items);
  });

  const one = Effect.fn("Gather.one")(function* (ownerId: UserId, id: GatherItemId) {
    const [found] = yield* read(ownerId, eq(gatherItem.id, id));
    if (!found) return yield* notFound();
    return found;
  });

  const week = Effect.fn("Gather.week")(function* (ownerId: UserId, weekStart: string) {
    const recipeCount = yield* sync(ownerId, weekStart);
    const items = yield* read(ownerId, eq(gatherItem.weekStart, weekStart));
    return { weekStart, recipeCount, items };
  });

  const add = Effect.fn("Gather.add")(function* (
    ownerId: UserId,
    weekStart: string,
    input: GatherItemInput,
  ) {
    const parsed = parseIngredientLine(input.line);
    const item = parsed.item.trim() === "" ? input.line : parsed.item;
    const itemKey = ingredientKey(item);
    const [row] = yield* db.use((d) =>
      d
        .insert(gatherItem)
        .values({
          ownerId,
          weekStart,
          item,
          itemKey,
          unit: parsed.unit,
          aisle: aisleFor(itemKey),
          manual: true,
          ...quantity.toRow(parsed.quantity),
        })
        .returning({ id: gatherItem.id }),
    );
    if (!row) return yield* invalid();
    return yield* one(ownerId, GatherItemId.make(row.id)).pipe(
      Effect.catchTag("NotFound", Effect.die),
    );
  });

  const update = Effect.fn("Gather.update")(function* (
    ownerId: UserId,
    id: GatherItemId,
    input: GatherItemUpdate,
  ) {
    return yield* db.transaction(
      Effect.gen(function* () {
        const found = yield* one(ownerId, id);
        if (input.checked !== undefined && input.checked !== found.checked) {
          yield* db.use((d) =>
            d
              .update(gatherItem)
              .set({ checked: input.checked })
              .where(and(eq(gatherItem.id, id), eq(gatherItem.ownerId, ownerId))),
          );
        }
        if (input.inPantry === true) {
          yield* db.use((d) =>
            d.insert(pantryItem).values({ ownerId, itemKey: found.itemKey }).onConflictDoNothing(),
          );
        } else if (input.inPantry === false) {
          yield* db.use((d) =>
            d
              .delete(pantryItem)
              .where(and(eq(pantryItem.ownerId, ownerId), eq(pantryItem.itemKey, found.itemKey))),
          );
        }
        return yield* one(ownerId, id);
      }),
    );
  });

  const remove = Effect.fn("Gather.remove")(function* (ownerId: UserId, id: GatherItemId) {
    const found = yield* one(ownerId, id);
    if (!found.manual) return yield* invalid();
    yield* db.use((d) =>
      d.delete(gatherItem).where(and(eq(gatherItem.id, id), eq(gatherItem.ownerId, ownerId))),
    );
    return found;
  });

  return { week, add, update, remove };
});

/** The Gather list: every read and write is scoped to one owner. */
export class Gather extends Context.Service<Gather, Effect.Success<typeof make>>()(
  "cauldron/api/Gather",
) {
  static readonly layer = Layer.effect(Gather, make);
}
