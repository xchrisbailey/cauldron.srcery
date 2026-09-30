import { Config, Context, Effect, Layer, Option, Redacted, Schema } from "effect";
import pkg from "../package.json" with { type: "json" };

export interface OAuthProviderConfig {
  readonly providerId: string;
  readonly clientId: string;
  readonly clientSecret: string;
  readonly discoveryUrl: string;
}

/** `NODE_ENV`; production turns on the strict configuration checks. */
export const NodeEnv = Config.Literals(["development", "test", "production"], "NODE_ENV").pipe(
  Config.withDefault("development"),
);

export const MIN_SECRET_LENGTH = 32;

const ProductionSecret = Config.schema(
  Schema.Redacted(
    Schema.String.check(
      Schema.isMinLength(MIN_SECRET_LENGTH, {
        message: `BETTER_AUTH_SECRET must be at least ${MIN_SECRET_LENGTH} characters in production (try: openssl rand -base64 32)`,
      }),
    ),
  ),
  "BETTER_AUTH_SECRET",
);

export interface SocialProviders {
  readonly google?: { readonly clientId: string; readonly clientSecret: Redacted.Redacted<string> };
  readonly apple?: {
    readonly clientId: string;
    readonly clientSecret: Redacted.Redacted<string>;
    readonly appBundleIdentifier: string | undefined;
  };
}

export class AppConfig extends Context.Service<
  AppConfig,
  {
    readonly port: number;
    /** Public origin the browser sees (the web app); auth cookies, redirects and CORS use it. */
    readonly publicUrl: string;
    readonly authSecret: Redacted.Redacted<string>;
    /**
     * Trust the `x-client-ip` header (set by our own web proxy) for the client's
     * address. Only enable behind that proxy; otherwise the header is spoofable.
     */
    readonly trustProxy: boolean;
    /** Serves Scalar API docs at /v1/docs. */
    readonly docs: boolean;
    readonly version: string;
    readonly commit: string | undefined;
    /** Google and Apple, each enabled when its credentials are set. */
    readonly social: SocialProviders;
    /** Optional generic OIDC provider, used in dev and tests in place of Google/Apple. Never in production. */
    readonly devOAuth: OAuthProviderConfig | undefined;
  }
>()("cauldron/api/AppConfig") {
  // Reads the environment once at boot and fails fast on anything missing.
  static readonly layer = Layer.effect(
    AppConfig,
    Effect.gen(function* () {
      const env = yield* NodeEnv;
      const production = env === "production";
      const port = yield* Config.Port("PORT").pipe(Config.withDefault(3001));
      // Production has no defaults: a missing PUBLIC_URL would quietly point
      // auth cookies and redirects at localhost.
      const publicUrl = yield* production
        ? Config.String("PUBLIC_URL")
        : Config.String("PUBLIC_URL").pipe(Config.withDefault("http://localhost:3000"));
      const authSecret = yield* production
        ? ProductionSecret
        : Config.Redacted("BETTER_AUTH_SECRET");
      const trustProxy = yield* Config.Boolean("TRUST_PROXY").pipe(Config.withDefault(false));
      const docs = yield* Config.Boolean("API_DOCS").pipe(Config.withDefault(env !== "production"));
      const commit = yield* Config.option(Config.String("GIT_SHA"));
      const devIssuer = yield* Config.option(Config.String("DEV_OAUTH_DISCOVERY_URL"));
      if (env === "production" && Option.isSome(devIssuer)) {
        return yield* Effect.die("DEV_OAUTH_DISCOVERY_URL must not be set in production.");
      }
      const google = yield* Config.option(
        Config.all({
          clientId: Config.String("GOOGLE_CLIENT_ID"),
          clientSecret: Config.Redacted("GOOGLE_CLIENT_SECRET"),
        }),
      );
      const apple = yield* Config.option(
        Config.all({
          clientId: Config.String("APPLE_CLIENT_ID"),
          clientSecret: Config.Redacted("APPLE_CLIENT_SECRET"),
        }),
      );
      const appleBundle = yield* Config.option(Config.String("APPLE_APP_BUNDLE_IDENTIFIER"));
      return AppConfig.of({
        port,
        publicUrl,
        authSecret,
        trustProxy,
        docs,
        version: pkg.version,
        commit: Option.getOrUndefined(commit),
        social: {
          ...(Option.isSome(google) ? { google: google.value } : {}),
          ...(Option.isSome(apple)
            ? { apple: { ...apple.value, appBundleIdentifier: Option.getOrUndefined(appleBundle) } }
            : {}),
        },
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
        trustProxy: false,
        docs: false,
        version: "0.0.0-test",
        commit: undefined,
        social: {},
        devOAuth: undefined,
        ...overrides,
      }),
    );
}
