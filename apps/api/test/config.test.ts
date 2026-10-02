import { assert, describe, it } from "@effect/vitest";
import { ConfigProvider, Effect, Exit, Layer, Redacted } from "effect";
import { AppConfig } from "../src/AppConfig.ts";
import { Db } from "../src/Db.ts";
import { Storage } from "../src/Storage.ts";

const SECRET = "x".repeat(32);
const PLACEHOLDER = "change-me-change-me-change-me-change-me";

const withEnv = (env: Record<string, string>) =>
  ConfigProvider.layer(ConfigProvider.fromEnvRecord(env));

const loadConfig = (env: Record<string, string>) =>
  Effect.exit(
    Effect.service(AppConfig).pipe(
      Effect.provide(AppConfig.layer.pipe(Layer.provide(withEnv(env)))),
    ),
  );

const failureText = (exit: Exit.Exit<unknown, unknown>) =>
  Exit.isFailure(exit) ? String(Exit.isFailure(exit) && exit.cause) : "";

const production = {
  NODE_ENV: "production",
  PUBLIC_URL: "https://cauldron.example",
  BETTER_AUTH_SECRET: SECRET,
};

describe("AppConfig", () => {
  it.effect("defaults PUBLIC_URL and trustProxy outside production", () =>
    Effect.gen(function* () {
      const exit = yield* loadConfig({ BETTER_AUTH_SECRET: "short" });
      assert.isTrue(Exit.isSuccess(exit));
      if (Exit.isSuccess(exit)) {
        assert.strictEqual(exit.value.publicUrl, "http://localhost:3000");
        assert.strictEqual(exit.value.trustProxy, false);
        assert.strictEqual(Redacted.value(exit.value.authSecret), "short");
      }
    }),
  );

  it.effect("accepts a complete production environment", () =>
    Effect.gen(function* () {
      const exit = yield* loadConfig({ ...production, TRUST_PROXY: "true" });
      assert.isTrue(Exit.isSuccess(exit));
      if (Exit.isSuccess(exit)) {
        assert.strictEqual(exit.value.publicUrl, "https://cauldron.example");
        assert.isTrue(exit.value.trustProxy);
        assert.isFalse(exit.value.docs);
      }
    }),
  );

  it.effect("production requires PUBLIC_URL", () =>
    Effect.gen(function* () {
      const { PUBLIC_URL: _, ...env } = production;
      const exit = yield* loadConfig(env);
      assert.isTrue(Exit.isFailure(exit));
      assert.include(failureText(exit), "PUBLIC_URL");
    }),
  );

  it.effect("production requires BETTER_AUTH_SECRET", () =>
    Effect.gen(function* () {
      const { BETTER_AUTH_SECRET: _, ...env } = production;
      const exit = yield* loadConfig(env);
      assert.isTrue(Exit.isFailure(exit));
      assert.include(failureText(exit), "BETTER_AUTH_SECRET");
    }),
  );

  it.effect("production rejects a secret under 32 characters, without echoing it", () =>
    Effect.gen(function* () {
      const exit = yield* loadConfig({ ...production, BETTER_AUTH_SECRET: "too-short-secret" });
      assert.isTrue(Exit.isFailure(exit));
      const text = failureText(exit);
      assert.include(text, "at least 32 characters");
      assert.notInclude(text, "too-short-secret");
    }),
  );

  it.effect("production rejects the example placeholder secret, without echoing it", () =>
    Effect.gen(function* () {
      const exit = yield* loadConfig({ ...production, BETTER_AUTH_SECRET: PLACEHOLDER });
      assert.isTrue(Exit.isFailure(exit));
      const text = failureText(exit);
      assert.include(text, "BETTER_AUTH_SECRET is the example placeholder");
      assert.notInclude(text, PLACEHOLDER);
    }),
  );

  it.effect("production rejects the placeholder in any letter case", () =>
    Effect.gen(function* () {
      const exit = yield* loadConfig({
        ...production,
        BETTER_AUTH_SECRET: PLACEHOLDER.toUpperCase(),
      });
      assert.isTrue(Exit.isFailure(exit));
      assert.include(failureText(exit), "BETTER_AUTH_SECRET is the example placeholder");
    }),
  );

  it.effect("development still accepts the example placeholder secret", () =>
    Effect.gen(function* () {
      const exit = yield* loadConfig({ BETTER_AUTH_SECRET: PLACEHOLDER });
      assert.isTrue(Exit.isSuccess(exit));
    }),
  );
});

describe("Db.layer", () => {
  const build = (env: Record<string, string>) =>
    Effect.exit(Layer.build(Db.layer).pipe(Effect.scoped, Effect.provide(withEnv(env))));

  it.effect("production requires DATABASE_URL instead of falling back to PGlite", () =>
    Effect.gen(function* () {
      const exit = yield* build({ NODE_ENV: "production" });
      assert.isTrue(Exit.isFailure(exit));
      assert.include(failureText(exit), "DATABASE_URL");
    }),
  );

  it.effect("outside production it falls back to in-memory PGlite", () =>
    Effect.gen(function* () {
      const exit = yield* build({});
      assert.isTrue(Exit.isSuccess(exit));
    }),
  );
});

describe("Storage.layer", () => {
  const build = (env: Record<string, string>) =>
    Effect.exit(Layer.build(Storage.layer).pipe(Effect.scoped, Effect.provide(withEnv(env))));

  it.effect("production refuses to boot without S3_BUCKET or STORAGE_DIR", () =>
    Effect.gen(function* () {
      const exit = yield* build({ NODE_ENV: "production" });
      assert.isTrue(Exit.isFailure(exit));
      assert.include(failureText(exit), "S3_BUCKET or STORAGE_DIR");
    }),
  );

  it.effect("production keeps photos on disk when STORAGE_DIR is set", () =>
    Effect.gen(function* () {
      const exit = yield* build({ NODE_ENV: "production", STORAGE_DIR: "/data/storage" });
      assert.isTrue(Exit.isSuccess(exit));
    }),
  );

  it.effect("outside production it defaults to a local folder", () =>
    Effect.gen(function* () {
      const exit = yield* build({});
      assert.isTrue(Exit.isSuccess(exit));
    }),
  );
});
