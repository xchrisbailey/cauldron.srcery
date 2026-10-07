import { schema } from "@cauldron/db";
import { copy } from "@cauldron/shared";
import { eq } from "drizzle-orm";
import { Effect } from "effect";
import { OAuth2Server } from "oauth2-mock-server";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import type { AppConfig } from "../src/AppConfig.ts";
import { Db } from "../src/Db.ts";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";

const PASSWORD = "correct-horse-1";

const signUp = (api: AuthApi, email: string) =>
  api.post("/v1/auth/sign-up/email", { email, password: PASSWORD, name: "Cook", callbackURL: "/" });

const userExists = (api: AuthApi, email: string) =>
  api.run(
    Effect.gen(function* () {
      const db = yield* Db;
      const rows = yield* db.use((d) =>
        d.select({ id: schema.user.id }).from(schema.user).where(eq(schema.user.email, email)),
      );
      return rows.length > 0;
    }),
  );

const signInOptions = async (api: AuthApi) =>
  (await (await api.send("/v1/sign-in-options")).json()) as { signUp: boolean };

/** A local OIDC provider and an API that uses it as the dev provider, under `config`. */
const withProvider = (config: Partial<AppConfig["Service"]>) => {
  const oidc = new OAuth2Server();
  let oidcEmail = "";
  let api: AuthApi;

  beforeAll(async () => {
    await oidc.issuer.keys.generate("RS256");
    await oidc.start(0, "127.0.0.1");
    const claims = () => ({
      sub: `sub-${oidcEmail}`,
      email: oidcEmail,
      name: "OAuth User",
      email_verified: true,
    });
    oidc.service.on("beforeUserinfo", (res) => {
      res.body = claims();
    });
    oidc.service.on("beforeTokenSigning", (token) => {
      Object.assign(token.payload, claims());
    });
    api = makeAuthApi({
      ...config,
      devOAuth: {
        providerId: "dev",
        clientId: "cauldron-dev",
        clientSecret: "cauldron-dev-secret",
        discoveryUrl: `${oidc.issuer.url}/.well-known/openid-configuration`,
      },
    });
  });

  afterAll(async () => {
    await api.dispose();
    await oidc.stop();
  });

  const oauthSignIn = async (email: string) => {
    oidcEmail = email;
    const start = await api.post("/v1/auth/sign-in/social", {
      provider: "dev",
      callbackURL: "/",
      errorCallbackURL: "/sign-in",
    });
    const { url: authorizeUrl } = (await start.json()) as { url: string };
    const stateCookies = start.headers
      .getSetCookie()
      .map((c) => c.split(";")[0])
      .join("; ");
    const authorize = await fetch(authorizeUrl, { redirect: "manual" });
    const callbackUrl = new URL(authorize.headers.get("location")!);
    return api.send(callbackUrl.pathname + callbackUrl.search, {
      headers: { cookie: stateCookies },
    });
  };

  return { api: () => api, oauthSignIn };
};

describe("sign-up closed", () => {
  const { api, oauthSignIn } = withProvider({ signUpMode: "closed" });

  it("refuses email sign-up, creates no user and sends nothing", async () => {
    const res = await signUp(api(), "stranger@example.com");
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ code: "EMAIL_PASSWORD_SIGN_UP_DISABLED" });
    await api().settle();
    expect(await api().outbox()).toHaveLength(0);
    expect(await userExists(api(), "stranger@example.com")).toBe(false);
  });

  it("sends a first-time provider sign-in back with SIGN_UP_CLOSED and creates no user", async () => {
    const res = await oauthSignIn("new-oauth@example.com");
    expect(res.status).toBe(302);
    const location = new URL(res.headers.get("location")!, "http://localhost:3000");
    expect(location.pathname).toBe("/sign-in");
    expect(location.searchParams.get("error")).toBe("SIGN_UP_CLOSED");
    expect(cookieOf(res)).toBeUndefined();
    expect(await userExists(api(), "new-oauth@example.com")).toBe(false);
  });

  it("still signs an existing user in through the provider", async () => {
    const email = "owner@example.com";
    await api().run(
      Effect.gen(function* () {
        const db = yield* Db;
        yield* db.use((d) =>
          d
            .insert(schema.user)
            .values({ id: "u_owner", name: "Owner", email, emailVerified: true }),
        );
      }),
    );
    const res = await oauthSignIn(email);
    expect(res.headers.get("location")).toBe("/");
    expect(cookieOf(res)).toBeTruthy();
  });

  it("tells the web app sign-up is off", async () => {
    expect(await signInOptions(api())).toMatchObject({ signUp: false });
  });
});

describe("sign-up by allowlist", () => {
  const { api, oauthSignIn } = withProvider({
    signUpMode: "allowlist",
    signUpAllowedEmails: ["listed@example.com", "listed-oauth@example.com"],
  });

  it("lets a listed address sign up, in any letter case", async () => {
    const res = await signUp(api(), "Listed@Example.com");
    expect(res.status).toBe(200);
    const sent = await api().waitForOutbox(1);
    expect(sent[0]!.subject).toBe(copy.auth.verifyEmailSubject.text);
    expect(await userExists(api(), "listed@example.com")).toBe(true);
  });

  it("refuses an unlisted address with a plain message, creates no user and sends nothing", async () => {
    const before = (await api().outbox()).length;
    const res = await signUp(api(), "stranger@example.com");
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({
      code: "SIGN_UP_CLOSED",
      message: copy.auth.signUpClosed.text,
    });
    await api().settle();
    expect(await api().outbox()).toHaveLength(before);
    expect(await userExists(api(), "stranger@example.com")).toBe(false);
  });

  it("applies the list to a first-time provider sign-in", async () => {
    const refused = await oauthSignIn("unlisted-oauth@example.com");
    expect(refused.headers.get("location")).toContain("error=SIGN_UP_CLOSED");
    expect(await userExists(api(), "unlisted-oauth@example.com")).toBe(false);

    const allowed = await oauthSignIn("listed-oauth@example.com");
    expect(allowed.headers.get("location")).toBe("/");
    expect(cookieOf(allowed)).toBeTruthy();
  });

  it("tells the web app sign-up is on", async () => {
    expect(await signInOptions(api())).toMatchObject({ signUp: true });
  });
});
