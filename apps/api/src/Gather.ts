import { schema } from "@cauldron/db";
import {
  addDays,
  aisleFor,
  type Aisle,
  copy,
  type GatherItem,
  GatherItemId,
  type GatherItemInput,
  type GatherItemUpdate,
  type GatherLine,
  gatherLines,
  type GatheredRow,
  ingredientKey,
  InvalidRequest,
  MAX_QUANTITY,
  mergeKeyOf,
  NotFound,
  parseIngredientLine,
  type Quantity,
  RecipeId,
  sortRows,
  UNITS,
  type UnitCode,
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

/** Quantities are stored as numeric(12, 4): round the same way so comparisons match. */
const round4 = (n: number) => Math.min(MAX_QUANTITY, Math.round(n * 10_000) / 10_000);
const stored = (q: Quantity | null) =>
  q === null
    ? { quantityMin: null, quantityMax: null }
    : { quantityMin: round4(q.min), quantityMax: q.max === null ? null : round4(q.max) };

const quantityOf = (min: number | null, max: number | null): Quantity | null =>
  min === null ? null : { min, max: max ?? null };

/** The most of a measure, in ml or g for volumes and masses, for spotting "needs more". */
const most = (q: Quantity | null, unit: UnitCode | null) =>
  q === null ? 0 : (q.max ?? q.min) * (unit === null ? 1 : UNITS[unit].factor);

type ItemRow = typeof gatherItem.$inferSelect;
type SourceRow = typeof gatherItemSource.$inferSelect;

const sourcesKey = (
  sources: ReadonlyArray<{
    recipeId: string;
    quantityMin: number | null;
    quantityMax: number | null;
    unit: string | null;
  }>,
) =>
  JSON.stringify(
    [...sources]
      .map((s) => [s.recipeId, s.quantityMin, s.quantityMax, s.unit])
      .sort((a, b) => String(a[0]).localeCompare(String(b[0]))),
  );

const make = Effect.gen(function* () {
  const db = yield* Db;

  /** Lines from the week's planned recipes, each scaled by its entry's servings. */
  const plannedLines = Effect.fn("Gather.plannedLines")(function* (
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
    if (recipeIds.length === 0) return { lines: [], recipeCount: 0 };
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
    const lines: Array<GatherLine> = [];
    for (const entry of entries) {
      const factor =
        entry.servings !== null && entry.recipeServings !== null
          ? entry.servings / entry.recipeServings
          : 1;
      for (const i of byRecipe.get(entry.recipeId) ?? []) {
        const q = quantityOf(i.quantityMin, i.quantityMax);
        lines.push({
          recipeId: entry.recipeId,
          item: i.item,
          itemKey: i.itemKey,
          quantity:
            q === null
              ? null
              : { min: q.min * factor, max: q.max === null ? null : q.max * factor },
          unit: i.unit as UnitCode | null,
        });
      }
    }
    return { lines, recipeCount: recipeIds.length };
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
                ...stored(s.quantity),
              })),
            ),
          )
          .pipe(Effect.asVoid);

  /**
   * Brings the gathered rows in line with the week's plan: rows still needed
   * are updated in place (keeping their check, unless the week now needs more),
   * new ones are added, and ones no longer needed are removed. Items added by
   * hand are never touched. A lock per owner and week keeps two syncs apart.
   */
  const sync = Effect.fn("Gather.sync")(function* (ownerId: UserId, weekStart: string) {
    return yield* db.transaction(
      Effect.gen(function* () {
        yield* db.use((d) =>
          d.execute(
            sql`select pg_advisory_xact_lock(hashtext(${`gather/${ownerId}/${weekStart}`}))`,
          ),
        );
        const { lines, recipeCount } = yield* plannedLines(ownerId, weekStart);
        const rows = gatherLines(lines);
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
        const existingSources: ReadonlyArray<SourceRow> =
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
        const byKey = new Map<string, ItemRow>();
        const stale: Array<string> = [];
        for (const row of existing) {
          const key = mergeKeyOf(
            row.itemKey,
            quantityOf(row.quantityMin, row.quantityMax),
            row.unit as UnitCode | null,
          );
          if (byKey.has(key)) stale.push(row.id);
          else byKey.set(key, row);
        }
        for (const row of rows) {
          const amount = stored(row.quantity);
          const found = byKey.get(row.mergeKey);
          if (!found) {
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
                  ...amount,
                })
                .returning({ id: gatherItem.id }),
            );
            yield* writeSources(ownerId, inserted!.id, row);
            continue;
          }
          byKey.delete(row.mergeKey);
          // Both sides as stored (rounded to numeric(12, 4)), so a 1/3 that
          // rounds down doesn't read as "more" on every sync.
          const grew =
            most(quantityOf(amount.quantityMin, amount.quantityMax), row.unit) >
            most(quantityOf(found.quantityMin, found.quantityMax), found.unit as UnitCode | null) *
              (1 + 1e-9);
          const changed =
            found.item !== row.item ||
            found.quantityMin !== amount.quantityMin ||
            found.quantityMax !== amount.quantityMax ||
            found.unit !== row.unit ||
            found.aisle !== row.aisle;
          if (changed || (grew && found.checked)) {
            yield* db.use((d) =>
              d
                .update(gatherItem)
                .set({
                  item: row.item,
                  unit: row.unit,
                  aisle: row.aisle,
                  ...amount,
                  ...(grew ? { checked: false } : {}),
                })
                .where(eq(gatherItem.id, found.id)),
            );
          }
          const want = sourcesKey(
            row.sources.map((s) => ({ recipeId: s.recipeId, unit: s.unit, ...stored(s.quantity) })),
          );
          if (want !== sourcesKey(sourcesOf.get(found.id) ?? [])) {
            yield* db.use((d) =>
              d.delete(gatherItemSource).where(eq(gatherItemSource.gatherItemId, found.id)),
            );
            yield* writeSources(ownerId, found.id, row);
          }
        }
        stale.push(...[...byKey.values()].map((row) => row.id));
        if (stale.length > 0) {
          yield* db.use((d) =>
            d
              .delete(gatherItem)
              .where(and(eq(gatherItem.ownerId, ownerId), inArray(gatherItem.id, stale))),
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
      quantity: quantityOf(row.quantityMin, row.quantityMax),
      unit: row.unit as UnitCode | null,
      aisle: (row.aisle ?? aisleFor(row.itemKey)) as Aisle,
      checked: row.checked,
      manual: row.manual,
      inPantry: Boolean(row.inPantry),
      sources: (sourcesOf.get(row.id) ?? []).map((s) => ({
        recipeId: RecipeId.make(s.recipeId),
        title: s.title,
        quantity: quantityOf(s.quantityMin, s.quantityMax),
        unit: s.unit as UnitCode | null,
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
          ...stored(parsed.quantity),
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
