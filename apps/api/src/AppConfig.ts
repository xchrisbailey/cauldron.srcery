import { Config, Context, Effect, Layer, Option, Redacted } from "effect";

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
    /** Public origin the browser sees (the web app); auth cookies and redirects use it. */
    readonly publicUrl: string;
    readonly authSecret: Redacted.Redacted<string>;
    /** PGlite data directory; undefined means in-memory. */
    readonly pgliteDataDir: string | undefined;
    /** Optional generic OIDC provider, used by the spike and tests in place of Google/Apple. */
    readonly devOAuth: OAuthProviderConfig | undefined;
  }
>()("cauldron/api/AppConfig") {
  static readonly layer = Layer.effect(
    AppConfig,
    Effect.gen(function* () {
      const port = yield* Config.Port("PORT").pipe(Config.withDefault(3001));
      const publicUrl = yield* Config.String("PUBLIC_URL").pipe(
        Config.withDefault("http://localhost:3000"),
      );
      const authSecret = yield* Config.Redacted("BETTER_AUTH_SECRET");
      const pgliteDataDir = yield* Config.option(Config.String("PGLITE_DATA_DIR"));
      const devIssuer = yield* Config.option(Config.String("DEV_OAUTH_DISCOVERY_URL"));
      return AppConfig.of({
        port,
        publicUrl,
        authSecret,
        pgliteDataDir: Option.getOrUndefined(pgliteDataDir),
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
        pgliteDataDir: undefined,
        devOAuth: undefined,
        ...overrides,
      }),
    );
}
