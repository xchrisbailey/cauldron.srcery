import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { bearer } from "better-auth/plugins/bearer";
import { genericOAuth } from "better-auth/plugins/generic-oauth";
import { schema } from "@cauldron/db";
import { copy } from "@cauldron/shared";
import { Context, Effect, Layer, Redacted } from "effect";
import { AppConfig } from "./AppConfig.ts";
import { Db } from "./Db.ts";
import { CLIENT_IP_HEADER } from "./http/ClientIp.ts";
import { type Email, Mailer } from "./Mailer.ts";

const makeAuth = (
  config: AppConfig["Service"],
  db: Db["Service"],
  sendEmail: (email: Email) => Promise<void>,
) => {
  const { google, apple } = config.social;
  return betterAuth({
    baseURL: config.publicUrl,
    basePath: "/v1/auth",
    secret: Redacted.value(config.authSecret),
    // Apple posts its callback from its own origin.
    trustedOrigins: [config.publicUrl, ...(apple ? ["https://appleid.apple.com"] : [])],
    database: drizzleAdapter(db.drizzle, {
      provider: "pg",
      schema: {
        user: schema.user,
        session: schema.session,
        account: schema.account,
        verification: schema.verification,
      },
    }),
    emailAndPassword: {
      enabled: true,
      requireEmailVerification: true,
      minPasswordLength: 8,
      revokeSessionsOnPasswordReset: true,
      sendResetPassword: ({ user, url }) =>
        sendEmail({
          to: user.email,
          subject: copy.auth.resetPasswordSubject.text,
          text: copy.auth.resetPasswordBody(url).text,
        }),
    },
    emailVerification: {
      sendOnSignUp: true,
      autoSignInAfterVerification: true,
      sendVerificationEmail: ({ user, url }) =>
        sendEmail({
          to: user.email,
          subject: copy.auth.verifyEmailSubject.text,
          text: copy.auth.verifyEmailBody(url).text,
        }),
    },
    socialProviders: {
      ...(google
        ? {
            google: {
              clientId: google.clientId,
              clientSecret: Redacted.value(google.clientSecret),
            },
          }
        : {}),
      ...(apple
        ? {
            apple: {
              clientId: apple.clientId,
              clientSecret: Redacted.value(apple.clientSecret),
              ...(apple.appBundleIdentifier
                ? { appBundleIdentifier: apple.appBundleIdentifier }
                : {}),
            },
          }
        : {}),
    },
    account: {
      accountLinking: {
        enabled: true,
        // Google and Apple verify emails, so signing in with them can join an
        // existing account, but never one whose own email is unconfirmed (that
        // would let someone pre-register a victim's address with a password).
        trustedProviders: ["google", "apple"],
        requireLocalEmailVerified: true,
      },
    },
    user: { deleteUser: { enabled: true } },
    // Better Auth only reads headers, never the socket. Follow the same rule as
    // http/ClientIp.ts: trust the web proxy's x-client-ip when configured to,
    // otherwise record no IP rather than believe a client-supplied header.
    advanced: {
      ipAddress: config.trustProxy
        ? { ipAddressHeaders: [CLIENT_IP_HEADER] }
        : { disableIpTracking: true },
    },
    plugins: [
      // Bearer tokens for the iOS app: sign-in responses carry `set-auth-token`,
      // and `Authorization: Bearer <token>` works wherever the cookie does.
      bearer(),
      genericOAuth({
        config: config.devOAuth
          ? [{ ...config.devOAuth, scopes: ["openid", "email", "profile"], pkce: true }]
          : [],
      }),
    ],
  });
};

export type AuthInstance = ReturnType<typeof makeAuth>;

export class Auth extends Context.Service<Auth, AuthInstance>()("cauldron/api/Auth") {
  static readonly layer = Layer.effect(
    Auth,
    Effect.gen(function* () {
      const config = yield* AppConfig;
      const db = yield* Db;
      const mailer = yield* Mailer;
      const context = yield* Effect.context<never>();
      // Better Auth awaits these, so a failed send surfaces as a failed request.
      const sendEmail = (email: Email) =>
        mailer.send(email).pipe(
          Effect.tapError((error) => Effect.logError("Couldn't send email", error.cause)),
          Effect.runPromiseWith(context),
        );
      return makeAuth(config, db, sendEmail);
    }),
  );
}
