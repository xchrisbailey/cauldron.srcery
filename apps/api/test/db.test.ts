import { schema } from "@cauldron/db";
import { assert, layer } from "@effect/vitest";
import { eq, sql } from "drizzle-orm";
import { Deferred, Effect, Fiber, Schema } from "effect";
import { Db, DbError, isInvalidText, isUniqueViolation, redactDbError } from "../src/Db.ts";

class TestFailure extends Schema.TaggedError<TestFailure>()("TestFailure", {}) {}

const newId = () => `u_${crypto.randomUUID()}`;

const insertUser = Effect.fn("insertUser")(function* (id: string) {
  const db = yield* Db;
  yield* db.use((d) =>
    d.insert(schema.user).values({ id, name: "Test", email: `${id}@example.test` }),
  );
});

const findUser = Effect.fn("findUser")(function* (id: string) {
  const db = yield* Db;
  const rows = yield* db.use((d) => d.select().from(schema.user).where(eq(schema.user.id, id)));
  return rows.length;
});

layer(Db.layerTest)("Db", (it) => {
  it.effect("ping succeeds", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      yield* db.ping;
    }),
  );

  it.effect("use works outside a transaction", () =>
    Effect.gen(function* () {
      const id = newId();
      yield* insertUser(id);
      assert.strictEqual(yield* findUser(id), 1);
    }),
  );

  it.effect("a SQL error surfaces as DbError", () =>
    Effect.gen(function* () {
      const id = newId();
      yield* insertUser(id);
      const error = yield* Effect.flip(insertUser(id));
      assert.strictEqual(error._tag, "DbError");
      assert.instanceOf(error, DbError);
    }),
  );

  it.effect("a unique violation keeps its Postgres code, and logging redacts the parameters", () =>
    Effect.gen(function* () {
      const id = newId();
      yield* insertUser(id);
      const error = yield* Effect.flip(insertUser(id));
      assert.strictEqual(error.code, "23505");
      assert.isTrue(isUniqueViolation(error));
      assert.isFalse(isInvalidText(error));
      const redacted = redactDbError(error);
      assert.strictEqual(redacted.code, "23505");
      assert.notInclude(redacted.message, id);
      assert.notInclude(redacted.message, "Failed query");
    }),
  );

  it.effect("an invalid text representation is flagged", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const error = yield* Effect.flip(db.use((d) => d.execute(sql`select 'nope'::uuid`)));
      assert.strictEqual(error.code, "22P02");
      assert.isTrue(isInvalidText(error));
    }),
  );

  it.effect("transaction commits on success", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const id = newId();
      const result = yield* db.transaction(insertUser(id).pipe(Effect.as("done")));
      assert.strictEqual(result, "done");
      assert.strictEqual(yield* findUser(id), 1);
    }),
  );

  it.effect("transaction rolls back on a typed failure and keeps the error typed", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const id = newId();
      const error = yield* Effect.flip(
        db.transaction(
          Effect.gen(function* () {
            yield* insertUser(id);
            assert.strictEqual(yield* findUser(id), 1); // visible inside
            return yield* new TestFailure();
          }),
        ),
      );
      assert.strictEqual(error._tag, "TestFailure");
      assert.strictEqual(yield* findUser(id), 0);
    }),
  );

  it.effect("transaction rolls back on a defect", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const id = newId();
      const exit = yield* Effect.exit(
        db.transaction(
          Effect.gen(function* () {
            yield* insertUser(id);
            return yield* Effect.die("boom");
          }),
        ),
      );
      assert.isTrue(exit._tag === "Failure");
      assert.strictEqual(yield* findUser(id), 0);
    }),
  );

  it.effect("a SQL error inside a transaction rolls back earlier writes", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const first = newId();
      const error = yield* Effect.flip(
        db.transaction(
          Effect.gen(function* () {
            yield* insertUser(first);
            yield* insertUser(first);
          }),
        ),
      );
      assert.strictEqual(error._tag, "DbError");
      assert.strictEqual(yield* findUser(first), 0);
    }),
  );

  it.effect("a nested transaction joins the outer one", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const outerId = newId();
      const innerId = newId();
      const error = yield* Effect.flip(
        db.transaction(
          Effect.gen(function* () {
            yield* insertUser(outerId);
            yield* db.transaction(insertUser(innerId));
            return yield* new TestFailure();
          }),
        ),
      );
      assert.strictEqual(error._tag, "TestFailure");
      assert.strictEqual(yield* findUser(outerId), 0);
      assert.strictEqual(yield* findUser(innerId), 0);
    }),
  );

  it.effect(
    "a nested transaction's failure, recovered inside, does not undo the outer commit",
    () =>
      Effect.gen(function* () {
        const db = yield* Db;
        const outerId = newId();
        yield* db.transaction(
          Effect.gen(function* () {
            yield* insertUser(outerId);
            yield* Effect.ignore(db.transaction(Effect.fail(new TestFailure())));
          }),
        );
        assert.strictEqual(yield* findUser(outerId), 1);
      }),
  );

  it.effect("interrupting a transaction interrupts its program and rolls back", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const id = newId();
      const inserted = yield* Deferred.make<void>();
      const finalized = yield* Deferred.make<void>();
      const fiber = yield* Effect.forkChild(
        db.transaction(
          Effect.gen(function* () {
            yield* insertUser(id);
            yield* Deferred.succeed(inserted, undefined);
            return yield* Effect.never;
          }).pipe(Effect.ensuring(Deferred.succeed(finalized, undefined))),
        ),
      );
      yield* Deferred.await(inserted);
      const exit = yield* Fiber.interrupt(fiber).pipe(Effect.andThen(Fiber.await(fiber)));
      assert.isTrue(exit._tag === "Failure");
      // The inner program was interrupted too (its finalizer ran).
      yield* Deferred.await(finalized);
      // The rollback finishes just after the interrupt returns.
      let rows = 1;
      for (let attempt = 0; attempt < 50 && rows > 0; attempt++) {
        rows = yield* findUser(id);
        if (rows > 0)
          yield* Effect.promise(() => new Promise((resolve) => setTimeout(resolve, 20)));
      }
      assert.strictEqual(rows, 0);
    }),
  );
});
