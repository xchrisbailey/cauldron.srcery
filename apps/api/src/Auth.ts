import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { bearer } from "better-auth/plugins/bearer";
import { genericOAuth } from "better-auth/plugins/generic-oauth";
import { schema } from "@cauldron/db";
import { Context, Effect, Layer, Redacted } from "effect";
import { AppConfig } from "./AppConfig.ts";
import { Db } from "./Db.ts";
import { CLIENT_IP_HEADER } from "./http/ClientIp.ts";

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
    // Better Auth only reads headers, never the socket. Follow the same rule as
    // http/ClientIp.ts: trust the web proxy's x-client-ip when configured to,
    // otherwise record no IP rather than believe a client-supplied header.
    advanced: {
      ipAddress: config.trustProxy
        ? { ipAddressHeaders: [CLIENT_IP_HEADER] }
        : { disableIpTracking: true },
    },
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
