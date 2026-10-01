import { schema, seedMany } from "@cauldron/db";
import { assert, layer } from "@effect/vitest";
import { and, count, eq, isNotNull, isNull, sql } from "drizzle-orm";
import { Effect } from "effect";
import { Db } from "../src/Db.ts";

layer(Db.layerTest)("seedMany", (it) => {
  it.effect("tops up to the count, with searchable structured recipes, and is idempotent", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const owner = `u_${crypto.randomUUID()}`;
      yield* db.use((d) =>
        d.insert(schema.user).values({ id: owner, name: "Test", email: `${owner}@example.test` }),
      );

      const first = yield* Effect.promise(() => seedMany(db.drizzle, owner, 60));
      assert.deepStrictEqual(first, { created: 60, total: 60 });

      const live = and(eq(schema.recipe.ownerId, owner), isNull(schema.recipe.deletedAt));
      const [recipes] = yield* db.use((d) =>
        d.select({ n: count() }).from(schema.recipe).where(live),
      );
      assert.strictEqual(recipes!.n, 60);

      const [searchable] = yield* db.use((d) =>
        d
          .select({ n: count() })
          .from(schema.recipe)
          .where(and(live, isNotNull(schema.recipe.search))),
      );
      assert.strictEqual(searchable!.n, 60);

      // Every recipe has 5-12 ingredients, all with an item_key, and 3-6 steps.
      const result = yield* db.use((d) =>
        d.execute(sql`
          select r.id,
            (select count(*)::int from recipe_ingredient i where i.recipe_id = r.id) as ingredients,
            (select count(*)::int from recipe_ingredient i where i.recipe_id = r.id and (i.item_key is null or i.item_key = '')) as missing_keys,
            (select count(*)::int from recipe_step s where s.recipe_id = r.id) as steps
          from recipe r where r.owner_id = ${owner}`),
      );
      const rows = (
        result as {
          rows: Array<{ ingredients: number; missing_keys: number; steps: number }>;
        }
      ).rows;
      assert.strictEqual(rows.length, 60);
      for (const row of rows) {
        assert.isTrue(row.ingredients >= 5 && row.ingredients <= 12);
        assert.strictEqual(row.missing_keys, 0);
        assert.isTrue(row.steps >= 3 && row.steps <= 6);
      }

      const again = yield* Effect.promise(() => seedMany(db.drizzle, owner, 60));
      assert.strictEqual(again.created, 0);
      const [after] = yield* db.use((d) =>
        d.select({ n: count() }).from(schema.recipe).where(live),
      );
      assert.strictEqual(after!.n, 60);
    }),
  );
});
