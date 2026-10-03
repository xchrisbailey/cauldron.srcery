import { macros, schema } from "@cauldron/db";
import {
  addDays,
  copy,
  dayTotals,
  type DiaryCopyInput,
  type Favourite,
  FavouriteId,
  type QuickFood,
  quickFoodKey,
  type RecentFood,
  daysBetween,
  type BodyProfile,
  type DiaryBatchInput,
  type DiaryDay,
  type DiaryEntry,
  DiaryEntryId,
  type DiaryEntryInput,
  type DiaryEntryUpdate,
  type IntakeDay,
  InvalidRequest,
  type LocalDate,
  type MacrosInput,
  type MealSlot,
  NotFound,
  RecipeId,
  type Targets,
  type TargetsInput,
  TRACKER_LIMITS,
  type TrackerRangeQuery,
  type TrackerSettings,
  type UserId,
  type WeighIn,
  type WeighInInput,
} from "@cauldron/shared";
import { and, asc, between, desc, eq, gte, sql, type SQL } from "drizzle-orm";
import { Context, Effect, Layer } from "effect";
import { Db } from "./Db.ts";
import { Recipes } from "./Recipes.ts";

const {
  diaryEntry: entry,
  recipe,
  bodyProfile,
  trackerTargets,
  trackerFavourite: favourite,
  weighIn,
} = schema;

const notFound = () => new NotFound({ message: copy.errors.notFound.text });
const invalid = () => new InvalidRequest({ message: copy.errors.invalidRequest.text });
const dayFull = () => new InvalidRequest({ message: copy.tracker.dayFull.text });

type EntryRow = typeof entry.$inferSelect;

const toEntry = (row: EntryRow): DiaryEntry => ({
  id: DiaryEntryId.make(row.id),
  date: row.date,
  slot: row.slot,
  name: row.name,
  amount: row.amount,
  servings: row.servings,
  macros: macros.fromRow(row),
  source: row.source,
  recipeId: row.recipeId === null ? null : RecipeId.make(row.recipeId),
  position: row.position,
});

/** How far back recents look. */
const RECENT_DAYS = 60;
const RECENT_MAX = 30;

const toFood = (row: {
  name: string;
  amount: string | null;
  servings: number;
  calories: number | null;
  proteinGrams: number | null;
  carbsGrams: number | null;
  fatGrams: number | null;
  source: DiaryEntry["source"];
  recipeId: string | null;
}): QuickFood => ({
  name: row.name,
  amount: row.amount,
  servings: row.servings,
  macros: macros.fromRow(row),
  source: row.source,
  recipeId: row.recipeId === null ? null : RecipeId.make(row.recipeId),
});

const toFavourite = (row: typeof favourite.$inferSelect): Favourite => ({
  id: FavouriteId.make(row.id),
  food: toFood(row),
});

const toTargets = (row: typeof trackerTargets.$inferSelect): Targets => ({
  calories: row.calories,
  protein: row.protein,
  carbs: row.carbs,
  fat: row.fat,
  overridden: {
    calories: row.caloriesOverridden,
    protein: row.proteinOverridden,
    carbs: row.carbsOverridden,
    fat: row.fatOverridden,
  },
  checkedInOn: row.checkedInOn,
});

const toProfile = (row: typeof bodyProfile.$inferSelect): BodyProfile => ({
  sex: row.sex,
  birthDate: row.birthDate,
  heightCm: row.heightCm,
  activity: row.activity,
  goal: row.goal,
  weeklyRateKg: row.weeklyRateKg,
  proteinPerKg: row.proteinPerKg,
  fatShare: row.fatShare,
  weightUnit: row.weightUnit,
  heightUnit: row.heightUnit,
});

/** Grams are stored to one decimal place; round before writing so a read matches. */
const tenth = (n: number | null) => (n === null ? null : Math.round(n * 10) / 10);
const macroColumns = (m: MacrosInput) =>
  macros.toRow({
    calories: m.calories,
    protein: tenth(m.protein),
    carbs: tenth(m.carbs),
    fat: tenth(m.fat),
  });

const make = Effect.gen(function* () {
  const db = yield* Db;
  const recipes = yield* Recipes;

  const select = (ownerId: UserId, where: SQL | undefined) =>
    db
      .use((d) =>
        d
          .select()
          .from(entry)
          .where(and(eq(entry.ownerId, ownerId), where))
          // The slot enum sorts in meal order: breakfast, lunch, dinner, snack.
          .orderBy(asc(entry.date), asc(entry.slot), asc(entry.position), asc(entry.createdAt)),
      )
      .pipe(Effect.map((rows) => rows.map(toEntry)));

  const one = Effect.fn("Tracker.one")(function* (ownerId: UserId, id: string) {
    const [found] = yield* select(ownerId, eq(entry.id, id));
    if (!found) return yield* notFound();
    return found;
  });

  const checkRange = Effect.fn("Tracker.checkRange")(function* (query: TrackerRangeQuery) {
    const days = daysBetween(query.from, query.to);
    if (days < 0 || days >= TRACKER_LIMITS.rangeDays) return yield* invalid();
  });

  /** Serializes writes to one day, so concurrent adds can't pass the limit or share a position. */
  const lockDay = (ownerId: UserId, date: string) =>
    db.use((d) =>
      d.execute(sql`select pg_advisory_xact_lock(hashtext(${`diary/${ownerId}/${date}`}))`),
    );

  const countDay = (ownerId: UserId, date: string) =>
    db
      .use((d) =>
        d
          .select({ n: sql<number>`count(*)::int` })
          .from(entry)
          .where(and(eq(entry.ownerId, ownerId), eq(entry.date, date))),
      )
      .pipe(Effect.map(([row]) => Number(row?.n ?? 0)));

  /** The next position at the end of a slot. */
  const nextPosition = (ownerId: UserId, date: string, slot: MealSlot) =>
    db
      .use((d) =>
        d
          .select({ n: sql<number>`coalesce(max(${entry.position}) + 1, 0)::int` })
          .from(entry)
          .where(and(eq(entry.ownerId, ownerId), eq(entry.date, date), eq(entry.slot, slot))),
      )
      .pipe(Effect.map(([row]) => Number(row?.n ?? 0)));

  const getTargets = (ownerId: UserId) =>
    db
      .use((d) => d.select().from(trackerTargets).where(eq(trackerTargets.ownerId, ownerId)))
      .pipe(Effect.map(([row]) => (row ? toTargets(row) : null)));

  const day = Effect.fn("Tracker.day")(function* (ownerId: UserId, date: LocalDate) {
    const entries = yield* select(ownerId, eq(entry.date, date));
    const targets = yield* getTargets(ownerId);
    const [weight] = yield* db.use((d) =>
      d
        .select({ date: weighIn.date, weightKg: weighIn.weightKg })
        .from(weighIn)
        .where(and(eq(weighIn.ownerId, ownerId), eq(weighIn.date, date))),
    );
    return {
      date,
      entries,
      totals: dayTotals(entries),
      targets,
      weighIn: weight ?? null,
    } satisfies DiaryDay;
  });

  const intake = Effect.fn("Tracker.intake")(function* (ownerId: UserId, query: TrackerRangeQuery) {
    yield* checkRange(query);
    const entries = yield* select(ownerId, between(entry.date, query.from, query.to));
    const byDay = new Map<string, Array<DiaryEntry>>();
    for (const e of entries) byDay.set(e.date, [...(byDay.get(e.date) ?? []), e]);
    return [...byDay].map(([date, list]): IntakeDay => ({
      date,
      entries: list.length,
      totals: dayTotals(list),
    }));
  });

  const add = Effect.fn("Tracker.add")(function* (ownerId: UserId, input: DiaryEntryInput) {
    let recipeId = input.recipeId ?? null;
    // Only a recipe entry names a recipe. A recipe entry may come without one
    // when its recipe is gone (re-logging, undo), as long as it brings its own
    // name and numbers.
    if (recipeId !== null && input.source !== "recipe") return yield* invalid();
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
        let name = input.name;
        let numbers = input.macros;
        if (recipeId !== null && (name === undefined || numbers === undefined)) {
          const live = yield* recipes
            .live(ownerId, RecipeId.make(recipeId))
            .pipe(Effect.catchTag("NotFound", () => invalid()));
          name ??= live.title;
          // Copied now, so later edits to the recipe leave this day alone.
          numbers ??= macros.fromRow(live);
        } else if (recipeId !== null) {
          // Everything was sent, so the recipe is only a link: keep it while
          // the cook still has the recipe (banished counts), and drop it
          // otherwise rather than refuse a re-log.
          const [own] = yield* db.use((d) =>
            d
              .select({ id: recipe.id })
              .from(recipe)
              .where(and(eq(recipe.id, recipeId!), eq(recipe.ownerId, ownerId))),
          );
          if (!own) recipeId = null;
        }
        if (name === undefined || numbers === undefined) return yield* invalid();
        yield* lockDay(ownerId, input.date);
        if ((yield* countDay(ownerId, input.date)) >= TRACKER_LIMITS.perDay) {
          return yield* dayFull();
        }
        const position = yield* nextPosition(ownerId, input.date, input.slot);
        const [row] = yield* db.use((d) =>
          d
            .insert(entry)
            .values({
              ...(input.id === undefined ? {} : { id: input.id }),
              ownerId,
              date: input.date,
              slot: input.slot,
              name,
              amount: input.amount || null,
              servings: input.servings,
              ...macroColumns(numbers),
              source: input.source,
              recipeId,
              position,
            })
            .returning({ id: entry.id }),
        );
        return yield* one(ownerId, row!.id).pipe(Effect.catchTag("NotFound", Effect.die));
      }),
    );
  });

  const addMany = Effect.fn("Tracker.addMany")(function* (ownerId: UserId, input: DiaryBatchInput) {
    // Each add joins this transaction, so one refusal undoes the lot.
    return yield* db.transaction(Effect.forEach(input.entries, (e) => add(ownerId, e)));
  });

  const update = Effect.fn("Tracker.update")(function* (
    ownerId: UserId,
    id: DiaryEntryId,
    input: DiaryEntryUpdate,
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
        const date = input.date ?? row.date;
        const slot = input.slot ?? row.slot;
        const moved = date !== row.date || slot !== row.slot;
        if (date !== row.date) {
          yield* lockDay(ownerId, date);
          if ((yield* countDay(ownerId, date)) >= TRACKER_LIMITS.perDay) return yield* dayFull();
        }
        yield* db.use((d) =>
          d
            .update(entry)
            .set({
              date,
              slot,
              ...(input.name === undefined ? {} : { name: input.name }),
              ...(input.amount === undefined ? {} : { amount: input.amount || null }),
              ...(input.servings === undefined ? {} : { servings: input.servings }),
              ...(input.macros === undefined ? {} : macroColumns(input.macros)),
            })
            .where(and(eq(entry.id, id), eq(entry.ownerId, ownerId))),
        );
        if (moved) {
          const position = yield* nextPosition(ownerId, date, slot);
          yield* db.use((d) =>
            d
              .update(entry)
              .set({ position })
              .where(and(eq(entry.id, id), eq(entry.ownerId, ownerId))),
          );
        }
        return yield* one(ownerId, id);
      }),
    );
  });

  const remove = Effect.fn("Tracker.remove")(function* (ownerId: UserId, id: DiaryEntryId) {
    const rows = yield* db.use((d) =>
      d
        .delete(entry)
        .where(and(eq(entry.id, id), eq(entry.ownerId, ownerId)))
        .returning(),
    );
    if (!rows[0]) return yield* notFound();
    return toEntry(rows[0]);
  });

  const copyDay = Effect.fn("Tracker.copyDay")(function* (ownerId: UserId, input: DiaryCopyInput) {
    const slot = input.slot ?? null;
    if (input.from === input.to) return yield* invalid();
    yield* db.transaction(
      Effect.gen(function* () {
        const source = yield* select(
          ownerId,
          and(eq(entry.date, input.from), slot === null ? undefined : eq(entry.slot, slot)),
        );
        if (source.length === 0) return;
        yield* lockDay(ownerId, input.to);
        if ((yield* countDay(ownerId, input.to)) + source.length > TRACKER_LIMITS.perDay) {
          return yield* dayFull();
        }
        const next = new Map<MealSlot, number>();
        const values: Array<typeof entry.$inferInsert> = [];
        for (const e of source) {
          const position = next.get(e.slot) ?? (yield* nextPosition(ownerId, input.to, e.slot));
          next.set(e.slot, position + 1);
          values.push({
            ownerId,
            date: input.to,
            slot: e.slot,
            name: e.name,
            amount: e.amount,
            servings: e.servings,
            ...macros.toRow(e.macros),
            source: e.source,
            recipeId: e.recipeId,
            position,
          });
        }
        yield* db.use((d) => d.insert(entry).values(values));
      }),
    );
    return yield* day(ownerId, input.to);
  });

  const quickFoods = Effect.fn("Tracker.quickFoods")(function* (ownerId: UserId, today?: string) {
    const favourites = yield* db
      .use((d) =>
        d
          .select()
          .from(favourite)
          .where(eq(favourite.ownerId, ownerId))
          .orderBy(asc(sql`lower(${favourite.name})`)),
      )
      .pipe(Effect.map((rows) => rows.map(toFavourite)));
    const since = addDays(today ?? new Date().toISOString().slice(0, 10), -RECENT_DAYS);
    const rows = yield* db.use((d) =>
      d
        .select()
        .from(entry)
        .where(and(eq(entry.ownerId, ownerId), gte(entry.date, since)))
        .orderBy(desc(entry.date), desc(entry.createdAt)),
    );
    const starred = new Map(favourites.map((f) => [quickFoodKey(f.food), f.id]));
    const groups = new Map<
      string,
      { food: QuickFood; count: number; lastLoggedOn: string; lastEntryId: DiaryEntryId }
    >();
    for (const row of rows) {
      const food = toFood(row);
      const key = quickFoodKey(food);
      const group = groups.get(key);
      // Rows come newest first, so the first one seen is how it was last logged.
      if (group) group.count++;
      else
        groups.set(key, {
          food,
          count: 1,
          lastLoggedOn: row.date,
          lastEntryId: DiaryEntryId.make(row.id),
        });
    }
    const recents = [...groups]
      .filter(([key]) => !starred.has(key))
      .map(([, g]): RecentFood => ({
        food: g.food,
        count: g.count,
        lastLoggedOn: g.lastLoggedOn,
        lastEntryId: g.lastEntryId,
      }))
      .sort((a, b) => b.count - a.count || b.lastLoggedOn.localeCompare(a.lastLoggedOn))
      .slice(0, RECENT_MAX);
    return { favourites, recents };
  });

  const star = Effect.fn("Tracker.favourite")(function* (ownerId: UserId, entryId: DiaryEntryId) {
    const logged = yield* one(ownerId, entryId);
    const food: QuickFood = {
      name: logged.name,
      amount: logged.amount,
      servings: logged.servings,
      macros: logged.macros,
      source: logged.source,
      recipeId: logged.recipeId,
    };
    const values = {
      name: food.name,
      amount: food.amount,
      servings: food.servings,
      ...macros.toRow(food.macros),
      source: food.source,
      recipeId: food.recipeId,
    };
    const [row] = yield* db.use((d) =>
      d
        .insert(favourite)
        .values({ ownerId, key: quickFoodKey(food), ...values })
        .onConflictDoUpdate({ target: [favourite.ownerId, favourite.key], set: values })
        .returning(),
    );
    return toFavourite(row!);
  });

  const unstar = Effect.fn("Tracker.unfavourite")(function* (ownerId: UserId, id: FavouriteId) {
    const [row] = yield* db.use((d) =>
      d
        .delete(favourite)
        .where(and(eq(favourite.id, id), eq(favourite.ownerId, ownerId)))
        .returning(),
    );
    if (!row) return yield* notFound();
    return toFavourite(row);
  });

  const settings = Effect.fn("Tracker.settings")(function* (ownerId: UserId) {
    const [profile] = yield* db.use((d) =>
      d.select().from(bodyProfile).where(eq(bodyProfile.ownerId, ownerId)),
    );
    return {
      profile: profile ? toProfile(profile) : null,
      targets: yield* getTargets(ownerId),
    } satisfies TrackerSettings;
  });

  const saveProfile = Effect.fn("Tracker.saveProfile")(function* (
    ownerId: UserId,
    input: BodyProfile,
  ) {
    const [row] = yield* db.use((d) =>
      d
        .insert(bodyProfile)
        .values({ ownerId, ...input })
        .onConflictDoUpdate({ target: bodyProfile.ownerId, set: { ...input } })
        .returning(),
    );
    return toProfile(row!);
  });

  const saveTargets = Effect.fn("Tracker.saveTargets")(function* (
    ownerId: UserId,
    input: TargetsInput,
  ) {
    const values = {
      calories: input.calories,
      protein: input.protein,
      carbs: input.carbs,
      fat: input.fat,
      caloriesOverridden: input.overridden.calories,
      proteinOverridden: input.overridden.protein,
      carbsOverridden: input.overridden.carbs,
      fatOverridden: input.overridden.fat,
      ...(input.checkedInOn === undefined ? {} : { checkedInOn: input.checkedInOn }),
    };
    const [row] = yield* db.use((d) =>
      d
        .insert(trackerTargets)
        .values({ ownerId, ...values })
        .onConflictDoUpdate({ target: trackerTargets.ownerId, set: values })
        .returning(),
    );
    return toTargets(row!);
  });

  const weighIns = Effect.fn("Tracker.weighIns")(function* (
    ownerId: UserId,
    query: TrackerRangeQuery,
  ) {
    yield* checkRange(query);
    return yield* db.use((d) =>
      d
        .select({ date: weighIn.date, weightKg: weighIn.weightKg })
        .from(weighIn)
        .where(and(eq(weighIn.ownerId, ownerId), between(weighIn.date, query.from, query.to)))
        .orderBy(asc(weighIn.date)),
    );
  });

  const saveWeighIn = Effect.fn("Tracker.saveWeighIn")(function* (
    ownerId: UserId,
    date: LocalDate,
    input: WeighInInput,
  ) {
    // Two decimal places are stored; round first so the reply matches a later read.
    const weightKg = Math.round(input.weightKg * 100) / 100;
    const [row] = yield* db.use((d) =>
      d
        .insert(weighIn)
        .values({ ownerId, date, weightKg })
        .onConflictDoUpdate({ target: [weighIn.ownerId, weighIn.date], set: { weightKg } })
        .returning({ date: weighIn.date, weightKg: weighIn.weightKg }),
    );
    return row! satisfies WeighIn;
  });

  const removeWeighIn = Effect.fn("Tracker.removeWeighIn")(function* (
    ownerId: UserId,
    date: LocalDate,
  ) {
    const [row] = yield* db.use((d) =>
      d
        .delete(weighIn)
        .where(and(eq(weighIn.ownerId, ownerId), eq(weighIn.date, date)))
        .returning({ date: weighIn.date, weightKg: weighIn.weightKg }),
    );
    if (!row) return yield* notFound();
    return row satisfies WeighIn;
  });

  return {
    day,
    intake,
    add,
    addMany,
    update,
    remove,
    copyDay,
    quickFoods,
    favourite: star,
    unfavourite: unstar,
    settings,
    saveProfile,
    saveTargets,
    weighIns,
    saveWeighIn,
    removeWeighIn,
  };
});

/** The tracker: diary entries, targets, profile and weigh-ins, every read and write scoped to one owner. */
export class Tracker extends Context.Service<Tracker, Effect.Success<typeof make>>()(
  "cauldron/api/Tracker",
) {
  static readonly layer = Layer.effect(Tracker, make).pipe(Layer.provide(Recipes.layer));
}
