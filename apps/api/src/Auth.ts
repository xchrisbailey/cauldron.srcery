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
      // Sign-up answers the same for a taken address; the owner hears about it here.
      onExistingUserSignUp: ({ user }) =>
        sendEmail({
          to: user.email,
          subject: copy.auth.alreadyHaveAccountSubject.text,
          text: copy.auth.alreadyHaveAccountBody(`${config.publicUrl}/sign-in`).text,
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
        // Better Auth links a provider sign-in to an existing account only when the
        // provider vouches for the email, and with this flag never into an account
        // whose own email is unconfirmed (that would let someone pre-register a
        // victim's address with a password and inherit the victim's sign-in).
        requireLocalEmailVerified: true,
      },
    },
    user: { deleteUser: { enabled: true } },
    session: {
      expiresIn: 60 * 60 * 24 * 7, // sessions last 7 days...
      updateAge: 60 * 60 * 24, // ...and slide forward at most once a day
      // Deleting an account without a password (social-only accounts) needs a
      // session this young, so a stale or stolen session can't wipe the account.
      freshAge: 60 * 15,
      // cookieCache is deliberately off: revocation (sign-out, deletion, password
      // reset, revoke-sessions) must take effect immediately, not after a cache expiry.
    },
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
      // Sends run in their own fiber and are never awaited, so a request's timing
      // and errors don't reveal whether an address has an account. Failures are logged.
      const sendEmail = (email: Email): Promise<void> => {
        Effect.runForkWith(context)(
          mailer.send(email).pipe(
            Effect.tapError((error) => Effect.logError("Couldn't send email", error.cause)),
            Effect.ignore,
          ),
        );
        return Promise.resolve();
      };
      return makeAuth(config, db, sendEmail);
    }),
  );
}
