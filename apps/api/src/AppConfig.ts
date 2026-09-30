import { Config, Context, Effect, Layer, Option, Redacted } from "effect";
import pkg from "../package.json" with { type: "json" };

export interface OAuthProviderConfig {
  readonly providerId: string;
  readonly clientId: string;
  readonly clientSecret: string;
  readonly discoveryUrl: string;
}

export class AppConfig extends Context.Service<
  AppConfig,
  {
    readonly port: number;
    /** Public origin the browser sees (the web app); auth cookies, redirects and CORS use it. */
    readonly publicUrl: string;
    readonly authSecret: Redacted.Redacted<string>;
    /** Serves Scalar API docs at /v1/docs. */
    readonly docs: boolean;
    readonly version: string;
    readonly commit: string | undefined;
    /** Optional generic OIDC provider, used in dev and tests in place of Google/Apple. */
    readonly devOAuth: OAuthProviderConfig | undefined;
  }
>()("cauldron/api/AppConfig") {
  // Reads the environment once at boot and fails fast on anything missing.
  static readonly layer = Layer.effect(
    AppConfig,
    Effect.gen(function* () {
      const port = yield* Config.Port("PORT").pipe(Config.withDefault(3001));
      const publicUrl = yield* Config.String("PUBLIC_URL").pipe(
        Config.withDefault("http://localhost:3000"),
      );
      const authSecret = yield* Config.Redacted("BETTER_AUTH_SECRET");
      const env = yield* Config.Literals(["development", "test", "production"], "NODE_ENV").pipe(
        Config.withDefault("development"),
      );
      const docs = yield* Config.Boolean("API_DOCS").pipe(Config.withDefault(env !== "production"));
      const commit = yield* Config.option(Config.String("GIT_SHA"));
      const devIssuer = yield* Config.option(Config.String("DEV_OAUTH_DISCOVERY_URL"));
      return AppConfig.of({
        port,
        publicUrl,
        authSecret,
        docs,
        version: pkg.version,
        commit: Option.getOrUndefined(commit),
        devOAuth: Option.match(devIssuer, {
          onNone: () => undefined,
          onSome: (discoveryUrl) => ({
            providerId: "dev",
            clientId: "cauldron-dev",
            clientSecret: "cauldron-dev-secret",
            discoveryUrl,
          }),
        }),
      });
    }),
  );

  static readonly layerTest = (overrides: Partial<AppConfig["Service"]> = {}) =>
    Layer.succeed(
      AppConfig,
      AppConfig.of({
        port: 0,
        publicUrl: "http://localhost:3000",
        authSecret: Redacted.make("test-secret-test-secret-test-secret"),
        docs: false,
        version: "0.0.0-test",
        commit: undefined,
        devOAuth: undefined,
        ...overrides,
      }),
    );
}
