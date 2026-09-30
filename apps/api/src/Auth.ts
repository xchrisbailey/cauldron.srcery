import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { bearer } from "better-auth/plugins/bearer";
import { genericOAuth } from "better-auth/plugins/generic-oauth";
import { schema } from "@cauldron/db";
import { Context, Effect, Layer, Redacted } from "effect";
import { AppConfig } from "./AppConfig.ts";
import { Db } from "./Db.ts";

const makeAuth = (config: AppConfig["Service"], db: Db["Service"]) =>
  betterAuth({
    baseURL: config.publicUrl,
    basePath: "/v1/auth",
    secret: Redacted.value(config.authSecret),
    trustedOrigins: [config.publicUrl],
    database: drizzleAdapter(db.drizzle, {
      provider: "pg",
      schema: {
        user: schema.user,
        session: schema.session,
        account: schema.account,
        verification: schema.verification,
      },
    }),
    emailAndPassword: { enabled: true },
    // The API sits behind the web server's /v1 proxy (or a load balancer), which sets X-Forwarded-For.
    advanced: { ipAddress: { ipAddressHeaders: ["x-forwarded-for"] } },
    plugins: [
      bearer(),
      genericOAuth({
        config: config.devOAuth
          ? [{ ...config.devOAuth, scopes: ["openid", "email", "profile"], pkce: true }]
          : [],
      }),
    ],
  });

export type AuthInstance = ReturnType<typeof makeAuth>;

export class Auth extends Context.Service<Auth, AuthInstance>()("cauldron/api/Auth") {
  static readonly layer = Layer.effect(
    Auth,
    Effect.gen(function* () {
      const config = yield* AppConfig;
      const db = yield* Db;
      return makeAuth(config, db);
    }),
  );
}
