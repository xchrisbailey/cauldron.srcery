import { mkdirSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { migrationsFolder, schema } from "@cauldron/db";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import { drizzle as drizzlePg } from "drizzle-orm/node-postgres";
import { migrate as migratePg } from "drizzle-orm/node-postgres/migrator";
import { drizzle as drizzlePglite } from "drizzle-orm/pglite";
import { migrate as migratePglite } from "drizzle-orm/pglite/migrator";
import { sql } from "drizzle-orm";
import { Config, Context, Effect, Exit, Layer, Option, Redacted, Schema } from "effect";
import pg from "pg";
import { NodeEnv } from "./AppConfig.ts";

export class DbError extends Schema.TaggedError<DbError>()("DbError", {
  cause: Schema.Defect(),
  /** The SQLSTATE (for example "23505"), when the driver reported one. */
  code: Schema.optional(Schema.String),
}) {}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

// pg and PGlite put the SQLSTATE on the error; Drizzle may wrap it in a
// DrizzleQueryError that keeps the original as `cause`.
const findCode = (cause: unknown): string | undefined => {
  for (let error = cause, depth = 0; isRecord(error) && depth < 5; depth++) {
    if (typeof error.code === "string") return error.code;
    error = error.cause;
  }
  return undefined;
};

/** Wraps a thrown driver error, keeping its Postgres error code. */
export const dbError = (cause: unknown) => new DbError({ cause, code: findCode(cause) });

/** A unique constraint was violated (SQLSTATE 23505). */
export const isUniqueViolation = (error: DbError) => error.code === "23505";

/** A value had the wrong text representation for its column type, such as a bad uuid (SQLSTATE 22P02). */
export const isInvalidText = (error: DbError) => error.code === "22P02";

/**
 * What is safe to log about a DbError. Drizzle's own message includes the
 * query parameters, so this reports the SQLSTATE and the driver's message only.
 */
export const redactDbError = (error: DbError): { code: string | undefined; message: string } => {
  let inner: unknown = error.cause;
  for (let depth = 0; isRecord(inner) && isRecord(inner.cause) && depth < 5; depth++) {
    inner = inner.cause;
  }
  const message =
    isRecord(inner) &&
    typeof inner.message === "string" &&
    !inner.message.startsWith("Failed query")
      ? inner.message
      : "query failed";
  return { code: error.code, message };
};

export type Drizzle = PgDatabase<PgQueryResultHKT, typeof schema>;

/** The transaction the current fiber is running in, if any. */
const CurrentTx = Context.Reference<Drizzle | undefined>("cauldron/api/Db/CurrentTx", {
  defaultValue: () => undefined,
});

// Carries a failed Exit out of a Drizzle transaction callback so Drizzle rolls
// back, and the typed failure is restored on the other side.
class RollbackSignal {
  constructor(readonly exit: Exit.Exit<unknown, unknown>) {}
}

export class Db extends Context.Service<
  Db,
  {
    /** The root Drizzle instance. Prefer `use`; Better Auth needs this directly. */
    readonly drizzle: Drizzle;
    /** Runs a query on the current transaction, or the root connection outside one. */
    readonly use: <A>(f: (db: Drizzle) => Promise<A>) => Effect.Effect<A, DbError>;
    /** Runs an Effect in a transaction: every `use` inside it joins the transaction. */
    readonly transaction: <A, E, R>(
      self: Effect.Effect<A, E, R>,
    ) => Effect.Effect<A, E | DbError, R>;
    /** `select 1`, for health checks. */
    readonly ping: Effect.Effect<void, DbError>;
  }
>()("cauldron/api/Db") {
  static readonly fromDrizzle = (db: Drizzle) => {
    const use = <A>(f: (db: Drizzle) => Promise<A>): Effect.Effect<A, DbError> =>
      Effect.gen(function* () {
        const tx = yield* CurrentTx;
        return yield* Effect.tryPromise({
          try: () => f(tx ?? db),
          catch: (cause) => dbError(cause),
        });
      });

    const transaction = <A, E, R>(self: Effect.Effect<A, E, R>) =>
      Effect.gen(function* () {
        const outer = yield* CurrentTx;
        // Nested calls join the outer transaction.
        if (outer) return yield* self;
        const context = yield* Effect.context<R>();
        const exit = yield* Effect.tryPromise({
          // Interrupting the Effect aborts the signal, which interrupts the
          // inner program; its non-success Exit then rolls the transaction back.
          try: (signal) =>
            db.transaction(async (tx) => {
              const fiber = Effect.runForkWith(Context.add(context, CurrentTx, tx))(self);
              const finished = new Promise<Exit.Exit<A, E>>((resolve) => {
                fiber.addObserver(resolve);
              });
              const interrupt = () => fiber.interruptUnsafe();
              if (signal.aborted) interrupt();
              else signal.addEventListener("abort", interrupt, { once: true });
              const exit = await finished;
              signal.removeEventListener("abort", interrupt);
              if (!Exit.isSuccess(exit)) throw new RollbackSignal(exit);
              return exit;
            }),
          catch: (cause) => (cause instanceof RollbackSignal ? cause : dbError(cause)),
        }).pipe(
          Effect.catchIf(
            (error): error is RollbackSignal => error instanceof RollbackSignal,
            (signal) => Effect.succeed(signal.exit as Exit.Exit<A, E>),
          ),
        );
        return yield* exit;
      });

    const ping = use((db) => db.execute(sql`select 1`)).pipe(Effect.asVoid);

    return Db.of({ drizzle: db, use, transaction, ping });
  };

  /** Postgres through node-postgres. Migrations run under an advisory lock so instances don't race. */
  static readonly layerPostgres = (url: Redacted.Redacted<string>) =>
    Layer.effect(
      Db,
      Effect.gen(function* () {
        const context = yield* Effect.context<never>();
        const pool = yield* Effect.acquireRelease(
          Effect.sync(() => {
            const pool = new pg.Pool({
              connectionString: Redacted.value(url),
              // Fail fast so /v1/health answers 503 when Postgres is unreachable.
              connectionTimeoutMillis: 5000,
            });
            // An idle client erroring (server restart, network drop) must not crash the process.
            pool.on("error", (error) => {
              Effect.runForkWith(context)(
                Effect.logWarning("Postgres pool error", {
                  code: findCode(error),
                  message: error.message,
                }),
              );
            });
            return pool;
          }),
          (pool) => Effect.promise(() => pool.end()),
        );
        yield* Effect.tryPromise({
          try: async () => {
            const client = await pool.connect();
            let failure: Error | undefined;
            try {
              // Don't wait forever behind a stuck instance: lock_timeout also
              // covers advisory locks. Cleared once we hold the lock so it
              // doesn't apply to the migrations themselves.
              await client.query("set lock_timeout = '60s'");
              await client.query("select pg_advisory_lock(7263541)");
              await client.query("reset lock_timeout");
              await migratePg(drizzlePg({ client, schema }), { migrationsFolder });
            } finally {
              try {
                await client.query("select pg_advisory_unlock(7263541)");
              } catch (error) {
                failure = error instanceof Error ? error : new Error(String(error));
              }
              // Destroying the connection also drops the session lock if unlock failed.
              client.release(failure);
            }
          },
          catch: (cause) => dbError(cause),
        });
        return Db.fromDrizzle(drizzlePg({ client: pool, schema }));
      }),
    );

  /** Postgres in process (WASM). `dataDir` undefined keeps it in memory. */
  static readonly layerPglite = (dataDir: string | undefined) =>
    Layer.effect(
      Db,
      Effect.gen(function* () {
        if (dataDir) yield* Effect.sync(() => mkdirSync(dataDir, { recursive: true }));
        const client = yield* Effect.acquireRelease(
          Effect.tryPromise({
            try: () => PGlite.create(dataDir),
            catch: (cause) => dbError(cause),
          }),
          (client) => Effect.promise(() => client.close()),
        );
        const db = drizzlePglite({ client, schema });
        yield* Effect.tryPromise({
          try: () => migratePglite(db, { migrationsFolder }),
          catch: (cause) => dbError(cause),
        });
        return Db.fromDrizzle(db);
      }),
    );

  /** Postgres when DATABASE_URL is set, otherwise PGlite (PGLITE_DATA_DIR, or in memory). Production requires DATABASE_URL. */
  static readonly layer = Layer.unwrap(
    Effect.gen(function* () {
      // Production must use Postgres: no silent fall back to an in-memory database.
      if ((yield* NodeEnv) === "production") {
        return Db.layerPostgres(yield* Config.Redacted("DATABASE_URL"));
      }
      const url = yield* Config.option(Config.Redacted("DATABASE_URL"));
      if (Option.isSome(url)) return Db.layerPostgres(url.value);
      const dataDir = yield* Config.option(Config.String("PGLITE_DATA_DIR"));
      return Db.layerPglite(Option.getOrUndefined(dataDir));
    }),
  );

  /**
   * A fresh, migrated database for one test run. With DATABASE_URL (as in CI)
   * it creates a throwaway database on that server and drops it afterwards;
   * otherwise it uses in-memory PGlite.
   */
  static readonly layerTest = Layer.unwrap(
    Effect.gen(function* () {
      const url = yield* Config.option(Config.String("DATABASE_URL"));
      if (Option.isNone(url)) return Db.layerPglite(undefined);
      const name = `cauldron_test_${crypto.randomUUID().replaceAll("-", "")}`;
      const admin = (query: string) =>
        Effect.tryPromise({
          try: async () => {
            const client = new pg.Client({ connectionString: url.value });
            await client.connect();
            try {
              await client.query(query);
            } finally {
              await client.end();
            }
          },
          catch: (cause) => dbError(cause),
        });
      yield* Effect.acquireRelease(admin(`create database "${name}"`), () =>
        admin(`drop database if exists "${name}" with (force)`).pipe(Effect.ignore),
      );
      const testUrl = new URL(url.value);
      testUrl.pathname = `/${name}`;
      return Db.layerPostgres(Redacted.make(testUrl.toString()));
    }),
  );
}
