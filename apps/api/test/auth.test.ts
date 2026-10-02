import { Api, Authorization } from "@cauldron/api-spec";
import { schema } from "@cauldron/db";
import { copy } from "@cauldron/shared";
import { eq } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import { HttpApi, HttpApiBuilder, HttpApiEndpoint, HttpApiGroup } from "effect/http-api";
import { OAuth2Server } from "oauth2-mock-server";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { Auth } from "../src/Auth.ts";
import { Db } from "../src/Db.ts";
import { AuthorizationLive } from "../src/http/Authorization.ts";
import { AuthRoute } from "../src/http/AuthRoute.ts";
import { RateLimitLive } from "../src/http/RateLimit.ts";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

const PASSWORD = "correct-horse-1";

/** Sign up and return the verification link from the email that went out. */
const signUp = async (api: AuthApi, email: string, name = "Test User") => {
  const before = (await api.outbox()).length;
  const res = await api.post("/v1/auth/sign-up/email", {
    email,
    password: PASSWORD,
    name,
    callbackURL: "/",
  });
  // The email goes out in a forked fiber, so wait for it to land.
  const sent = (await api.waitForOutbox(before + 1)).slice(before).filter((m) => m.to === email);
  return { res, sent };
};

/** Sign up, follow the verification link, and return the session cookie it signs in with. */
const signUpVerified = async (api: AuthApi, email: string) => {
  const { sent } = await signUp(api, email);
  const verify = await api.send(api.linkIn(sent[0]!));
  const cookie = cookieOf(verify);
  if (!cookie) throw new Error(`verification didn't sign in (status ${verify.status})`);
  return cookie;
};

const signIn = (api: AuthApi, email: string, password = PASSWORD) =>
  api.post("/v1/auth/sign-in/email", { email, password });

const me = (api: AuthApi, headers: Record<string, string>) =>
  api.send("/v1/account/me", { headers });

describe("email and password", () => {
  let api: AuthApi;
  beforeAll(() => {
    api = makeAuthApi();
  });
  afterAll(() => api.dispose());

  it("sign-up sends one verification email and doesn't start a session", async () => {
    const { res, sent } = await signUp(api, "signup@example.com");
    expect(res.status).toBe(200);
    expect(cookieOf(res)).toBeUndefined();
    expect(res.headers.get("set-auth-token")).toBeNull();
    expect(sent).toHaveLength(1);
    expect(sent[0]!.subject).toBe(copy.auth.verifyEmailSubject.text);
    expect(api.linkIn(sent[0]!)).toMatch(/^\/v1\/auth\/verify-email\?token=/);
  });

  it("refuses to sign in before the email is verified", async () => {
    await signUp(api, "unverified@example.com");
    const res = await signIn(api, "unverified@example.com");
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ code: "EMAIL_NOT_VERIFIED" });
    expect(cookieOf(res)).toBeUndefined();
  });

  it("verifies through the link, signs in, then signs in again with a bearer token", async () => {
    const email = "ada@example.com";
    const { sent } = await signUp(api, email, "Ada");

    const verify = await api.send(api.linkIn(sent[0]!));
    expect(verify.status).toBe(302);
    expect(verify.headers.get("location")).toBe("/");
    const verifiedCookie = cookieOf(verify);
    expect(verifiedCookie).toBeTruthy();

    const viaVerifyCookie = await me(api, { cookie: verifiedCookie! });
    expect(viaVerifyCookie.status).toBe(200);
    expect(await viaVerifyCookie.json()).toMatchObject({ email, name: "Ada" });

    const login = await signIn(api, email);
    expect(login.status).toBe(200);
    const cookie = cookieOf(login);
    expect(cookie).toBeTruthy();
    expect((await me(api, { cookie: cookie! })).status).toBe(200);

    // The iOS stand-in: no cookie, no Origin, just the bearer token.
    const token = login.headers.get("set-auth-token");
    expect(token).toBeTruthy();
    const viaBearer = await me(api, { authorization: `Bearer ${token}` });
    expect(viaBearer.status).toBe(200);
    expect(await viaBearer.json()).toMatchObject({ email });

    const badBearer = await me(api, { authorization: "Bearer not-a-real-token" });
    expect(badBearer.status).toBe(401);
  });

  it("rejects a wrong password and an unknown account the same way", async () => {
    await signUpVerified(api, "wrongpw@example.com");
    const wrong = await signIn(api, "wrongpw@example.com", "not-the-password");
    const unknown = await signIn(api, "nobody@example.com");
    expect(wrong.status).toBe(401);
    expect(unknown.status).toBe(401);
    expect(await wrong.json()).toEqual(await unknown.json());
  });

  it("rejects a tampered verification token without signing in", async () => {
    const { sent } = await signUp(api, "tamper@example.com");
    const link = api.linkIn(sent[0]!);
    const res = await api.send(link.replace(/token=[^&]+/, "token=garbage"));
    expect(cookieOf(res)).toBeUndefined();
    expect((await signIn(api, "tamper@example.com")).status).toBe(403);
  });

  it("tells the owner when someone signs up with their address, and answers the same", async () => {
    const email = "taken@example.com";
    await signUpVerified(api, email);
    const before = (await api.outbox()).length;
    const again = await api.post("/v1/auth/sign-up/email", {
      email,
      password: "another-pass-5",
      name: "Someone Else",
    });
    const fresh = await api.post("/v1/auth/sign-up/email", {
      email: "brand-new@example.com",
      password: "another-pass-5",
      name: "Someone Else",
    });
    expect(again.status).toBe(fresh.status);
    expect(cookieOf(again)).toBeUndefined();
    const sent = (await api.waitForOutbox(before + 2)).slice(before);
    const note = sent.find((m) => m.to === email)!;
    expect(note.subject).toBe(copy.auth.alreadyHaveAccountSubject.text);
    expect(note.text).toContain(`${WEB_ORIGIN}/sign-in`);
    expect(note.text).not.toMatch(/verify-email/);
  });

  it("rejects short passwords", async () => {
    const res = await api.post("/v1/auth/sign-up/email", {
      email: "short@example.com",
      password: "short",
      name: "Short",
    });
    expect(res.status).toBe(400);
  });
});

describe("password reset", () => {
  let api: AuthApi;
  beforeAll(() => {
    api = makeAuthApi();
  });
  afterAll(() => api.dispose());

  const requestReset = (email: string) =>
    api.post("/v1/auth/request-password-reset", { email, redirectTo: "/reset-password" });

  it("resets the password, revokes old sessions and burns the token", async () => {
    const email = "reset@example.com";
    const oldCookie = await signUpVerified(api, email);
    expect((await me(api, { cookie: oldCookie })).status).toBe(200);

    const before = (await api.outbox()).length;
    const request = await requestReset(email);
    expect(request.status).toBe(200);
    const sent = (await api.waitForOutbox(before + 1)).slice(before);
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({ to: email, subject: copy.auth.resetPasswordSubject.text });

    // The emailed link redirects to the web page with the token attached.
    const link = await api.send(api.linkIn(sent[0]!));
    expect(link.status).toBe(302);
    const target = new URL(link.headers.get("location")!, WEB_ORIGIN);
    expect(target.pathname).toBe("/reset-password");
    const token = target.searchParams.get("token")!;
    expect(token).toBeTruthy();

    const newPassword = "brand-new-pass-2";
    const reset = await api.post("/v1/auth/reset-password", { newPassword, token });
    expect(reset.status).toBe(200);

    expect((await me(api, { cookie: oldCookie })).status).toBe(401);
    expect((await signIn(api, email)).status).toBe(401);
    const fresh = await signIn(api, email, newPassword);
    expect(fresh.status).toBe(200);
    expect((await me(api, { cookie: cookieOf(fresh)! })).status).toBe(200);

    // A used token doesn't work twice.
    const again = await api.post("/v1/auth/reset-password", {
      newPassword: "yet-another-pass-3",
      token,
    });
    expect(again.status).toBe(400);
    expect((await signIn(api, email, "yet-another-pass-3")).status).toBe(401);
  });

  it("answers the same for unknown emails and sends nothing", async () => {
    await signUpVerified(api, "known@example.com");
    const start = (await api.outbox()).length;
    const known = await requestReset("known@example.com");
    const before = (await api.waitForOutbox(start + 1)).length;
    const unknown = await requestReset("ghost@example.com");
    expect(unknown.status).toBe(known.status);
    expect(await unknown.json()).toEqual(await known.json());
    await api.settle();
    expect(await api.outbox()).toHaveLength(before);
  });

  it("rejects an invalid token", async () => {
    const res = await api.post("/v1/auth/reset-password", {
      newPassword: "whatever-pass-4",
      token: "not-a-token",
    });
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ code: "INVALID_TOKEN" });
  });
});

describe("delete account", () => {
  let api: AuthApi;
  beforeAll(() => {
    api = makeAuthApi();
  });
  afterAll(() => api.dispose());

  it("needs the right password", async () => {
    const cookie = await signUpVerified(api, "keep@example.com");
    const res = await api.post("/v1/auth/delete-user", { password: "wrong-password" }, { cookie });
    expect(res.status).toBe(400);
    expect((await me(api, { cookie })).status).toBe(200);
  });

  it("deletes the account, ends the session and blocks sign-in", async () => {
    const email = "gone@example.com";
    const cookie = await signUpVerified(api, email);

    const res = await api.post("/v1/auth/delete-user", { password: PASSWORD }, { cookie });
    expect(res.status).toBe(200);

    expect((await me(api, { cookie })).status).toBe(401);
    expect((await signIn(api, email)).status).toBe(401);
  });
});

describe("anonymous access", () => {
  let api: AuthApi;
  beforeAll(() => {
    api = makeAuthApi();
  });
  afterAll(() => api.dispose());

  const guarded = Object.values(Api.groups).flatMap((group) =>
    Object.values(group.endpoints)
      .filter((endpoint) => endpoint.middlewares.has(Authorization))
      .map((endpoint) => ({
        label: `${endpoint.method} ${endpoint.path}`,
        method: endpoint.method,
        // Path params get a dummy value.
        path: endpoint.path.replace(/:[A-Za-z0-9_]+\??/g, "00000000-0000-0000-0000-000000000000"),
      })),
  );

  it("has guarded endpoints to check", () => {
    expect(guarded.length).toBeGreaterThan(0);
  });

  it.each(guarded)("$label is 401 with the standard body", async ({ method, path }) => {
    const write = method !== "GET" && method !== "HEAD";
    // Writes carry the web origin so the 401 comes from the session check, not the CSRF guard.
    const res = await api.send(path, {
      method,
      headers: write ? { origin: WEB_ORIGIN, "content-type": "application/json" } : {},
      ...(write ? { body: "{}" } : {}),
    });
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({
      error: { code: "unauthorized", message: copy.errors.unauthorized.text },
    });
  });
});

describe("CSRF guard", () => {
  class Things extends HttpApiGroup.make("things")
    .add(
      HttpApiEndpoint.post("create", "/things", { success: Schema.Struct({ ok: Schema.Boolean }) }),
    )
    .middleware(Authorization) {}
  class TestApi extends HttpApi.make("csrf-test").add(Things).prefix("/v1") {}

  const ThingsLive = HttpApiBuilder.group(TestApi, "things", (handlers) =>
    Effect.succeed(handlers.handle("create", () => Effect.succeed({ ok: true }))),
  );

  // The real session check and CSRF guard, in front of a write endpoint that doesn't exist yet.
  const routes = Layer.mergeAll(
    HttpApiBuilder.layer(TestApi).pipe(Layer.provide(ThingsLive), Layer.provide(AuthorizationLive)),
    AuthRoute,
  ).pipe(Layer.provide([Auth.layer, RateLimitLive]));

  let api: AuthApi;
  let cookie: string;
  let token: string;
  beforeAll(async () => {
    api = makeAuthApi({}, routes);
    cookie = await signUpVerified(api, "csrf@example.com");
    const login = await signIn(api, "csrf@example.com");
    token = login.headers.get("set-auth-token")!;
  });
  afterAll(() => api.dispose());

  const create = (headers: Record<string, string>) =>
    api.send("/v1/things", { method: "POST", headers, body: "{}" });

  it("rejects a cookie POST with no Origin", async () => {
    const res = await create({ cookie });
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({
      error: { code: "forbidden", message: copy.errors.crossSite.text },
    });
  });

  it("rejects a cookie POST from another origin", async () => {
    const res = await create({ cookie, origin: "https://evil.example" });
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ error: { code: "forbidden" } });
  });

  it("lets a cookie POST from the web origin through", async () => {
    const res = await create({ cookie, origin: WEB_ORIGIN });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("rejects a cookie plus a bearer header from another origin", async () => {
    const res = await create({
      cookie,
      authorization: "Bearer a.b",
      origin: "https://evil.example",
    });
    expect(res.status).toBe(403);
    expect(await res.json()).toMatchObject({ error: { code: "forbidden" } });
  });

  it("lets a bearer POST through without an Origin", async () => {
    const res = await create({ authorization: `Bearer ${token}` });
    expect(res.status).toBe(200);
  });

  it("still 401s an anonymous POST from the web origin", async () => {
    const res = await create({ origin: WEB_ORIGIN });
    expect(res.status).toBe(401);
  });
});

describe("OAuth account linking", () => {
  const oidc = new OAuth2Server();
  let oidcEmail = "";
  let api: AuthApi;

  beforeAll(async () => {
    await oidc.issuer.keys.generate("RS256");
    await oidc.start(0, "127.0.0.1");
    oidc.service.on("beforeUserinfo", (res) => {
      res.body = {
        sub: `sub-${oidcEmail}`,
        email: oidcEmail,
        name: "OAuth User",
        email_verified: true,
      };
    });
    oidc.service.on("beforeTokenSigning", (token) => {
      token.payload.sub = `sub-${oidcEmail}`;
      token.payload.email = oidcEmail;
      token.payload.name = "OAuth User";
      token.payload.email_verified = true;
    });
    api = makeAuthApi({
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
    const start = await api.post("/v1/auth/sign-in/social", { provider: "dev", callbackURL: "/" });
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

  it("creates an account and signs in when the email is new", async () => {
    const res = await oauthSignIn("fresh-oauth@example.com");
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toBe("/");
    const cookie = cookieOf(res);
    expect(cookie).toBeTruthy();
    const session = await me(api, { cookie: cookie! });
    expect(session.status).toBe(200);
    expect(await session.json()).toMatchObject({ email: "fresh-oauth@example.com" });
  });

  it("doesn't link into an unverified password account with the same email", async () => {
    const email = "victim@example.com";
    // Someone pre-registers the victim's address and never verifies it.
    await signUp(api, email, "Squatter");

    const res = await oauthSignIn(email);
    expect(cookieOf(res)).toBeUndefined();
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toMatch(/error=/);

    // The squatter's password still can't sign in either.
    expect((await signIn(api, email)).status).toBe(403);
  });

  it("lets a social-only user with a fresh session delete their account without a password", async () => {
    const email = "social-only@example.com";
    const cookie = cookieOf(await oauthSignIn(email))!;
    expect((await me(api, { cookie })).status).toBe(200);
    const res = await api.post("/v1/auth/delete-user", {}, { cookie });
    expect(res.status).toBe(200);
    expect((await me(api, { cookie })).status).toBe(401);
  });

  /** Every cookie a response sets (session_token, plus session_data if the cookie cache is ever turned on), as one header. */
  const jarOf = (res: Response) =>
    res.headers
      .getSetCookie()
      .map((c) => c.split(";")[0]!)
      .filter((pair) => !pair.endsWith("="))
      .join("; ");

  /** Pretend the session was created `ms` ago. */
  const ageSession = (email: string, ms: number) =>
    api.run(
      Effect.gen(function* () {
        const db = yield* Db;
        const [row] = yield* db.use((d) =>
          d.select({ id: schema.user.id }).from(schema.user).where(eq(schema.user.email, email)),
        );
        yield* db.use((d) =>
          d
            .update(schema.session)
            .set({ createdAt: new Date(Date.now() - ms) })
            .where(eq(schema.session.userId, row!.id)),
        );
      }),
    );

  it("won't delete a social-only account from a session older than freshAge", async () => {
    const email = "stale-social@example.com";
    const cookie = cookieOf(await oauthSignIn(email))!;
    await ageSession(email, 16 * 60 * 1000);
    // Still a valid session, just not a fresh one.
    expect((await me(api, { cookie })).status).toBe(200);
    const res = await api.post("/v1/auth/delete-user", {}, { cookie });
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ code: "SESSION_EXPIRED" });
    expect((await me(api, { cookie })).status).toBe(200);
  });

  it("still deletes a social-only account from a session inside freshAge", async () => {
    const email = "fresh-social@example.com";
    const cookie = cookieOf(await oauthSignIn(email))!;
    await ageSession(email, 10 * 60 * 1000);
    const res = await api.post("/v1/auth/delete-user", {}, { cookie });
    expect(res.status).toBe(200);
  });

  it("rejects a replayed session cookie after sign-out", async () => {
    const jar = jarOf(await oauthSignIn("replay-signout@example.com"));
    expect((await me(api, { cookie: jar })).status).toBe(200);
    const out = await api.post("/v1/auth/sign-out", {}, { cookie: jar });
    expect(out.status).toBe(200);
    expect((await me(api, { cookie: jar })).status).toBe(401);
    expect((await api.send("/v1/recipes", { headers: { cookie: jar } })).status).toBe(401);
  });

  it("rejects a replayed session cookie after the account is deleted", async () => {
    const jar = jarOf(await oauthSignIn("replay-delete@example.com"));
    expect((await me(api, { cookie: jar })).status).toBe(200);
    expect((await api.post("/v1/auth/delete-user", {}, { cookie: jar })).status).toBe(200);
    expect((await me(api, { cookie: jar })).status).toBe(401);
    expect((await api.send("/v1/recipes", { headers: { cookie: jar } })).status).toBe(401);
  });

  it("links into a verified password account with the same email", async () => {
    const email = "linked@example.com";
    await signUpVerified(api, email);
    const res = await oauthSignIn(email);
    expect(res.headers.get("location")).toBe("/");
    expect(cookieOf(res)).toBeTruthy();
  });
});
