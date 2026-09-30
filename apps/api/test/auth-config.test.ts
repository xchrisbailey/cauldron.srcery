import { ConfigProvider, Effect, Exit, Layer, Redacted } from "effect";
import { describe, expect, it } from "vite-plus/test";
import { AppConfig } from "../src/AppConfig.ts";
import { Mailer, maskEmail } from "../src/Mailer.ts";

// Everything production requires, so these tests fail only for the reason they're about.
const PRODUCTION = {
  NODE_ENV: "production",
  PUBLIC_URL: "https://cauldron.example",
  DATABASE_URL: "postgres://localhost/cauldron",
  BETTER_AUTH_SECRET: "x".repeat(32),
};

const load = (env: Record<string, string>) =>
  Effect.runPromiseExit(
    Effect.service(AppConfig).pipe(
      Effect.provide(
        AppConfig.layer.pipe(
          Layer.provide(
            ConfigProvider.layer(
              ConfigProvider.fromUnknown({ BETTER_AUTH_SECRET: "s3cret", ...env }),
            ),
          ),
        ),
      ),
    ),
  );

const loaded = async (env: Record<string, string>) => {
  const exit = await load(env);
  if (!Exit.isSuccess(exit)) throw new Error(`config failed: ${String(exit.cause)}`);
  return exit.value;
};

describe("AppConfig.layer", () => {
  it("reads defaults", async () => {
    const config = await loaded({});
    expect(config.publicUrl).toBe("http://localhost:3000");
    expect(config.social).toEqual({});
    expect(config.devOAuth).toBeUndefined();
    expect(config.docs).toBe(true);
  });

  it("fails without an auth secret", async () => {
    const exit = await Effect.runPromiseExit(
      Effect.service(AppConfig).pipe(
        Effect.provide(
          AppConfig.layer.pipe(Layer.provide(ConfigProvider.layer(ConfigProvider.fromUnknown({})))),
        ),
      ),
    );
    expect(Exit.isFailure(exit)).toBe(true);
  });

  describe("dev OIDC provider", () => {
    const discovery = "http://localhost:9400/.well-known/openid-configuration";

    it("is enabled outside production", async () => {
      const config = await loaded({ DEV_OAUTH_DISCOVERY_URL: discovery });
      expect(config.devOAuth).toMatchObject({ providerId: "dev", discoveryUrl: discovery });
    });

    it("refuses to boot in production", async () => {
      const exit = await load({ ...PRODUCTION, DEV_OAUTH_DISCOVERY_URL: discovery });
      expect(Exit.isFailure(exit)).toBe(true);
      expect(String(exit)).toContain("DEV_OAUTH_DISCOVERY_URL must not be set in production");
    });

    it("is fine to leave unset in production", async () => {
      const config = await loaded(PRODUCTION);
      expect(config.devOAuth).toBeUndefined();
      expect(config.docs).toBe(false);
    });
  });

  describe("social providers", () => {
    it("loads Google and Apple when both id and secret are present", async () => {
      const config = await loaded({
        GOOGLE_CLIENT_ID: "g-id",
        GOOGLE_CLIENT_SECRET: "g-secret",
        APPLE_CLIENT_ID: "a-id",
        APPLE_CLIENT_SECRET: "a-secret",
        APPLE_APP_BUNDLE_IDENTIFIER: "io.srcery.cauldron",
      });
      expect(config.social.google?.clientId).toBe("g-id");
      expect(Redacted.value(config.social.google!.clientSecret)).toBe("g-secret");
      expect(config.social.apple?.clientId).toBe("a-id");
      expect(Redacted.value(config.social.apple!.clientSecret)).toBe("a-secret");
      expect(config.social.apple?.appBundleIdentifier).toBe("io.srcery.cauldron");
    });

    it("skips a provider that has only an id or only a secret", async () => {
      const config = await loaded({
        GOOGLE_CLIENT_ID: "g-id",
        APPLE_CLIENT_SECRET: "a-secret",
      });
      expect(config.social).toEqual({});
    });

    it("loads each provider independently", async () => {
      const config = await loaded({ GOOGLE_CLIENT_ID: "g-id", GOOGLE_CLIENT_SECRET: "g-secret" });
      expect(config.social.google).toBeDefined();
      expect(config.social.apple).toBeUndefined();
    });
  });
});

describe("Mailer.layer", () => {
  const loadMailer = (env: Record<string, string>) =>
    Effect.runPromiseExit(
      Effect.service(Mailer).pipe(
        Effect.provide(
          Mailer.layer.pipe(Layer.provide(ConfigProvider.layer(ConfigProvider.fromUnknown(env)))),
        ),
      ),
    );

  it("uses the console mailer outside production without a key", async () => {
    expect(Exit.isSuccess(await loadMailer({}))).toBe(true);
  });

  it("refuses to boot in production without RESEND_API_KEY", async () => {
    const exit = await loadMailer({ NODE_ENV: "production", EMAIL_FROM: "Cauldron <a@b.example>" });
    expect(Exit.isFailure(exit)).toBe(true);
    expect(String(exit)).toContain("RESEND_API_KEY and EMAIL_FROM must be set in production");
  });

  it("refuses to boot in production without EMAIL_FROM", async () => {
    const exit = await loadMailer({ NODE_ENV: "production", RESEND_API_KEY: "re_test" });
    expect(Exit.isFailure(exit)).toBe(true);
    expect(String(exit)).toContain("RESEND_API_KEY and EMAIL_FROM must be set in production");
  });

  it("boots in production with both set", async () => {
    const exit = await loadMailer({
      NODE_ENV: "production",
      RESEND_API_KEY: "re_test",
      EMAIL_FROM: "Cauldron <a@b.example>",
    });
    expect(Exit.isSuccess(exit)).toBe(true);
  });

  it("masks the recipient", () => {
    expect(maskEmail("ada@example.com")).toBe("a***@example.com");
    expect(maskEmail("nonsense")).toBe("***");
  });
});
