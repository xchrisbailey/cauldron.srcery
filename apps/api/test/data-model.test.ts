import { migrationsFolder, schema, seed } from "@cauldron/db";
import { assert, layer } from "@effect/vitest";
import { count, eq, sql } from "drizzle-orm";
import { migrate as migratePg } from "drizzle-orm/node-postgres/migrator";
import { migrate as migratePglite } from "drizzle-orm/pglite/migrator";
import { Effect } from "effect";
import { Db, isUniqueViolation } from "../src/Db.ts";

const rowsOf = <T = Record<string, unknown>>(result: unknown): Array<T> =>
  (result as { rows: Array<T> }).rows;

const newId = () => `u_${crypto.randomUUID()}`;

const insertUser = Effect.fn("insertUser")(function* () {
  const db = yield* Db;
  const id = newId();
  yield* db.use((d) =>
    d.insert(schema.user).values({ id, name: "Test", email: `${id}@example.test` }),
  );
  return id;
});

const insertRecipe = Effect.fn("insertRecipe")(function* (
  ownerId: string,
  values: Partial<typeof schema.recipe.$inferInsert> = {},
) {
  const db = yield* Db;
  const rows = yield* db.use((d) =>
    d
      .insert(schema.recipe)
      .values({ ownerId, title: "Test recipe", ...values })
      .returning(),
  );
  const row = rows[0];
  return row!;
});

const insertIngredient = Effect.fn("insertIngredient")(function* (
  ownerId: string,
  recipeId: string,
  values: Partial<typeof schema.recipeIngredient.$inferInsert> = {},
) {
  const db = yield* Db;
  yield* db.use((d) =>
    d
      .insert(schema.recipeIngredient)
      .values({ ownerId, recipeId, position: 0, item: "flour", originalLine: "flour", ...values }),
  );
});

const ownedTables = [
  ["recipe", schema.recipe],
  ["recipe_ingredient", schema.recipeIngredient],
  ["recipe_step", schema.recipeStep],
  ["tag", schema.tag],
  ["recipe_tag", schema.recipeTag],
  ["meal_plan_entry", schema.mealPlanEntry],
  ["gather_item", schema.gatherItem],
] as const;

const countFor = Effect.fn("countFor")(function* (
  table: (typeof ownedTables)[number][1],
  ownerId: string,
) {
  const db = yield* Db;
  const [row] = yield* db.use((d) =>
    d.select({ n: count() }).from(table).where(eq(table.ownerId, ownerId)),
  );
  return row!.n;
});

layer(Db.layerTest)("data model", (it) => {
  it.effect("migrations create every table", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const result = yield* db.use((d) =>
        d.execute(
          sql`select table_name from information_schema.tables where table_schema = 'public'`,
        ),
      );
      const names = new Set(rowsOf<{ table_name: string }>(result).map((r) => r.table_name));
      for (const name of [
        "user",
        "session",
        "account",
        "verification",
        ...ownedTables.map(([n]) => n),
      ]) {
        assert.isTrue(names.has(name), `missing table ${name}`);
      }
    }),
  );

  it.effect("running the migrator again is a no-op", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const snapshot = () =>
        db.use((d) =>
          d.execute(
            sql`select table_name, column_name, data_type from information_schema.columns where table_schema = 'public' order by 1, 2`,
          ),
        );
      const before = yield* snapshot();
      yield* Effect.promise(async () => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const d = db.drizzle as any;
        if (process.env.DATABASE_URL) await migratePg(d, { migrationsFolder });
        else await migratePglite(d, { migrationsFolder });
      });
      assert.deepStrictEqual(rowsOf(yield* snapshot()), rowsOf(before));
    }),
  );

  it.effect("seed loads 5 recipes with ingredients, steps and tags, and is idempotent", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const owner = yield* insertUser();
      const first = yield* Effect.promise(() => seed(db.drizzle, owner));
      assert.deepStrictEqual(first, { created: 5, total: 5 });
      const again = yield* Effect.promise(() => seed(db.drizzle, owner));
      assert.strictEqual(again.created, 0);

      assert.strictEqual(yield* countFor(schema.recipe, owner), 5);
      assert.isAbove(yield* countFor(schema.tag, owner), 0);
      // Vegetarian and Breakfast are shared between recipes: one tag row each.
      const tags = yield* db.use((d) =>
        d.select().from(schema.tag).where(eq(schema.tag.ownerId, owner)),
      );
      const names = tags.map((t) => t.name);
      assert.strictEqual(new Set(names).size, names.length);

      const recipes = yield* db.use((d) =>
        d.select().from(schema.recipe).where(eq(schema.recipe.ownerId, owner)),
      );
      for (const r of recipes) {
        const ings = yield* db.use((d) =>
          d
            .select()
            .from(schema.recipeIngredient)
            .where(eq(schema.recipeIngredient.recipeId, r.id)),
        );
        const steps = yield* db.use((d) =>
          d.select().from(schema.recipeStep).where(eq(schema.recipeStep.recipeId, r.id)),
        );
        const rts = yield* db.use((d) =>
          d.select().from(schema.recipeTag).where(eq(schema.recipeTag.recipeId, r.id)),
        );
        assert.isAbove(ings.length, 0, r.title);
        assert.isAbove(steps.length, 0, r.title);
        assert.isAbove(rts.length, 0, r.title);
        assert.isTrue(ings.every((i) => i.item.length > 0 && i.originalLine.length > 0));
        assert.isAbove(r.servings ?? 0, 0);
      }
    }),
  );

  it.effect("seeded ingredients are structured and keep original_line exactly", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const owner = yield* insertUser();
      yield* Effect.promise(() => seed(db.drizzle, owner));
      const rows = yield* db.use((d) =>
        d
          .select({ ing: schema.recipeIngredient, title: schema.recipe.title })
          .from(schema.recipeIngredient)
          .innerJoin(schema.recipe, eq(schema.recipe.id, schema.recipeIngredient.recipeId))
          .where(eq(schema.recipeIngredient.ownerId, owner)),
      );
      const find = (title: string, line: string) =>
        rows.find((r) => r.title === title && r.ing.originalLine === line)?.ing;

      const oil = find("Shakshuka with feta", "2 tbsp olive oil");
      assert.isDefined(oil);
      assert.strictEqual(oil!.quantityMin, 2);
      assert.strictEqual(oil!.unit, "tbsp");
      assert.strictEqual(oil!.item, "olive oil");

      // The raw line survives exactly, including the unicode fraction.
      const feta = find("Shakshuka with feta", "½ cup crumbled feta");
      assert.isDefined(feta);
      assert.strictEqual(feta!.quantityMin, 0.5);

      const range = find("Overnight oats", "1-2 tbsp maple syrup");
      assert.isDefined(range);
      assert.strictEqual(range!.quantityMin, 1);
      assert.strictEqual(range!.quantityMax, 2);

      const berries = find("Overnight oats", "1 cup berries");
      assert.strictEqual(berries?.section, "To serve");
      const almonds = find("Overnight oats", "2 tbsp toasted almonds, chopped");
      assert.strictEqual(almonds?.section, "To serve");
      const oats = find("Overnight oats", "1 cup rolled oats");
      assert.isNull(oats!.section);
      assert.isFalse(rows.some((r) => r.ing.originalLine.startsWith("##")));
      assert.isFalse(rows.some((r) => r.ing.item === "To serve"));
      // 9 lines less the heading.
      assert.strictEqual(rows.filter((r) => r.title === "Overnight oats").length, 8);
    }),
  );

  it.effect("every owned row has owner_id, and deleting the user cascades only their rows", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const a = yield* insertUser();
      const b = yield* insertUser();
      for (const owner of [a, b]) {
        yield* Effect.promise(() => seed(db.drizzle, owner));
        const r = yield* insertRecipe(owner);
        yield* db.use((d) =>
          d.insert(schema.mealPlanEntry).values({
            ownerId: owner,
            date: "2026-01-05",
            slot: "dinner",
            recipeId: r.id,
            title: "x",
          }),
        );
        yield* db.use((d) =>
          d
            .insert(schema.gatherItem)
            .values({ ownerId: owner, weekStart: "2026-01-05", item: "eggs" }),
        );
      }
      const before: Record<string, number> = {};
      for (const [name, table] of ownedTables) {
        before[name] = yield* countFor(table, b);
        assert.isAbove(yield* countFor(table, a), 0, `${name} has rows for a`);
        assert.isAbove(before[name]!, 0, name);
      }
      yield* db.use((d) => d.execute(sql`delete from "user" where id = ${a}`));
      for (const [name, table] of ownedTables) {
        assert.strictEqual(yield* countFor(table, a), 0, `${name} cascaded`);
        assert.strictEqual(yield* countFor(table, b), before[name], `${name} kept for b`);
      }
    }),
  );

  it.effect("ingredient positions are unique per recipe", () =>
    Effect.gen(function* () {
      const owner = yield* insertUser();
      const r1 = yield* insertRecipe(owner);
      const r2 = yield* insertRecipe(owner);
      yield* insertIngredient(owner, r1.id, { position: 0 });
      yield* insertIngredient(owner, r2.id, { position: 0 });
      const error = yield* Effect.flip(insertIngredient(owner, r1.id, { position: 0 }));
      assert.strictEqual(error._tag, "DbError");
      assert.isTrue(isUniqueViolation(error));
    }),
  );

  it.effect("a range with max below min is rejected as a DbError", () =>
    Effect.gen(function* () {
      const owner = yield* insertUser();
      const r = yield* insertRecipe(owner);
      const bad = yield* Effect.flip(
        insertIngredient(owner, r.id, { quantityMin: 3, quantityMax: 2 }),
      );
      assert.strictEqual(bad._tag, "DbError");
      assert.strictEqual(bad.code, "23514");
      const noMin = yield* Effect.flip(insertIngredient(owner, r.id, { quantityMax: 2 }));
      assert.strictEqual(noMin.code, "23514");
      yield* insertIngredient(owner, r.id, { position: 1, quantityMin: 2, quantityMax: 2 });
      yield* insertIngredient(owner, r.id, { position: 2, quantityMin: 1, quantityMax: 2 });
    }),
  );

  it.effect("servings must be positive", () =>
    Effect.gen(function* () {
      const owner = yield* insertUser();
      const zero = yield* Effect.flip(insertRecipe(owner, { servings: 0 }));
      assert.strictEqual(zero._tag, "DbError");
      assert.strictEqual(zero.code, "23514");
      const negative = yield* Effect.flip(insertRecipe(owner, { servings: -2 }));
      assert.strictEqual(negative.code, "23514");
      yield* insertRecipe(owner, { servings: 1 });
      yield* insertRecipe(owner, { servings: null });
    }),
  );

  it.effect("tag names are unique per owner, case-insensitively", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const a = yield* insertUser();
      const b = yield* insertUser();
      const add = (ownerId: string, name: string) =>
        db.use((d) => d.insert(schema.tag).values({ ownerId, name }));
      yield* add(a, "Vegan");
      const error = yield* Effect.flip(add(a, "vegan"));
      assert.isTrue(isUniqueViolation(error));
      yield* add(b, "Vegan");
    }),
  );

  it.effect("deleting a recipe cascades to its children and unlinks plan entries", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const owner = yield* insertUser();
      const r = yield* insertRecipe(owner);
      yield* insertIngredient(owner, r.id);
      yield* db.use((d) =>
        d
          .insert(schema.recipeStep)
          .values({ ownerId: owner, recipeId: r.id, position: 0, text: "Go" }),
      );
      const [t] = yield* db.use((d) =>
        d.insert(schema.tag).values({ ownerId: owner, name: "Quick" }).returning(),
      );
      yield* db.use((d) =>
        d.insert(schema.recipeTag).values({ ownerId: owner, recipeId: r.id, tagId: t!.id }),
      );
      yield* db.use((d) =>
        d.insert(schema.mealPlanEntry).values({
          ownerId: owner,
          date: "2026-01-05",
          slot: "lunch",
          recipeId: r.id,
          title: "Test recipe",
        }),
      );

      yield* db.use((d) => d.delete(schema.recipe).where(eq(schema.recipe.id, r.id)));

      assert.strictEqual(yield* countFor(schema.recipe, owner), 0);
      assert.strictEqual(yield* countFor(schema.recipeIngredient, owner), 0);
      assert.strictEqual(yield* countFor(schema.recipeStep, owner), 0);
      assert.strictEqual(yield* countFor(schema.recipeTag, owner), 0);
      // The tag itself stays.
      assert.strictEqual(yield* countFor(schema.tag, owner), 1);
      const entries = yield* db.use((d) =>
        d.select().from(schema.mealPlanEntry).where(eq(schema.mealPlanEntry.ownerId, owner)),
      );
      assert.strictEqual(entries.length, 1);
      assert.isNull(entries[0]!.recipeId);
      assert.strictEqual(entries[0]!.title, "Test recipe");
    }),
  );

  it.effect("timestamps have millisecond precision", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const owner = yield* insertUser();
      yield* insertRecipe(owner);
      // Read as text so no driver rounds it: microseconds would show 6 digits.
      const result = yield* db.use((d) =>
        d.execute(
          sql`select created_at::text as c, updated_at::text as u,
              extract(microseconds from created_at)::bigint % 1000 as sub
              from recipe where owner_id = ${owner}`,
        ),
      );
      const row = rowsOf<{ c: string; u: string; sub: string | number }>(result)[0]!;
      assert.strictEqual(Number(row.sub), 0);
      assert.match(row.c, /:\d\d(\.\d{1,3})?[+-]\d\d/);
      assert.match(row.u, /:\d\d(\.\d{1,3})?[+-]\d\d/);
    }),
  );

  it.effect("every timestamp column is declared with millisecond precision", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const result = yield* db.use((d) =>
        d.execute(
          sql`select table_name, column_name, datetime_precision from information_schema.columns
              where table_schema = 'public' and data_type = 'timestamp with time zone'`,
        ),
      );
      const columns = rowsOf<{
        table_name: string;
        column_name: string;
        datetime_precision: number;
      }>(result);
      assert.isAbove(columns.length, 0);
      for (const c of columns) {
        assert.strictEqual(Number(c.datetime_precision), 3, `${c.table_name}.${c.column_name}`);
      }
    }),
  );
});
