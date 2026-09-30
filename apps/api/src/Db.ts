import { mkdirSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { migrationsFolder, schema } from "@cauldron/db";
import { drizzle, type PgliteDatabase } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";
import { Context, Effect, Layer, Schema } from "effect";
import { AppConfig } from "./AppConfig.ts";

export class DbError extends Schema.TaggedError<DbError>()("DbError", {
  cause: Schema.Defect(),
}) {}

export type Drizzle = PgliteDatabase<typeof schema>;

export class Db extends Context.Service<
  Db,
  {
    readonly drizzle: Drizzle;
    readonly use: <A>(f: (db: Drizzle) => Promise<A>) => Effect.Effect<A, DbError>;
  }
>()("cauldron/api/Db") {
  static readonly make = Effect.gen(function* () {
    const { pgliteDataDir } = yield* AppConfig;
    if (pgliteDataDir) yield* Effect.sync(() => mkdirSync(pgliteDataDir, { recursive: true }));
    const client = yield* Effect.acquireRelease(
      Effect.promise(() => PGlite.create(pgliteDataDir)),
      (c) => Effect.promise(() => c.close()),
    );
    const db = drizzle({ client, schema });
    yield* Effect.tryPromise({
      try: () => migrate(db, { migrationsFolder }),
      catch: (cause) => new DbError({ cause }),
    });
    const use = <A>(f: (db: Drizzle) => Promise<A>) =>
      Effect.tryPromise({ try: () => f(db), catch: (cause) => new DbError({ cause }) });
    return Db.of({ drizzle: db, use });
  });

  static readonly layer = Layer.effect(Db, Db.make);
}
