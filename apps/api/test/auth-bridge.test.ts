import { OAuth2Server } from "oauth2-mock-server";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { makeTestApi, sessionCookie, url, WEB_ORIGIN } from "./helpers.ts";

describe("Better Auth bridge", () => {
  const oidc = new OAuth2Server();
  let api: ReturnType<typeof makeTestApi>;

  beforeAll(async () => {
    await oidc.issuer.keys.generate("RS256");
    await oidc.start(0, "127.0.0.1");
    oidc.service.on("beforeUserinfo", (res) => {
      res.body = {
        sub: "oidc-user-1",
        email: "oauth@example.com",
        name: "OAuth User",
        email_verified: true,
      };
    });
    oidc.service.on("beforeTokenSigning", (token) => {
      token.payload.email = "oauth@example.com";
      token.payload.name = "OAuth User";
      token.payload.email_verified = true;
    });
    api = makeTestApi({
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

  it("serves health without auth", async () => {
    const res = await api.handler(new Request(url("/v1/health")));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "ok", database: "ok" });
  });

  it("rejects anonymous requests to data routes", async () => {
    const res = await api.handler(new Request(url("/v1/account/me")));
    expect(res.status).toBe(401);
  });

  it("signs up with email and reads /me with the session cookie and with a bearer token", async () => {
    const signUp = await api.handler(
      new Request(url("/v1/auth/sign-up/email"), {
        method: "POST",
        headers: { "content-type": "application/json", origin: WEB_ORIGIN },
        body: JSON.stringify({
          email: "ada@example.com",
          password: "correct-horse-1",
          name: "Ada",
        }),
      }),
    );
    expect(signUp.status).toBe(200);

    const viaCookie = await api.handler(
      new Request(url("/v1/account/me"), { headers: { cookie: sessionCookie(signUp) } }),
    );
    expect(viaCookie.status).toBe(200);
    expect(await viaCookie.json()).toMatchObject({ email: "ada@example.com", name: "Ada" });

    const token = signUp.headers.get("set-auth-token");
    expect(token).toBeTruthy();
    const viaBearer = await api.handler(
      new Request(url("/v1/account/me"), { headers: { authorization: `Bearer ${token}` } }),
    );
    expect(viaBearer.status).toBe(200);
  });

  it("completes an OAuth redirect and callback through the bridge", async () => {
    // 1. Start the flow: Better Auth returns the provider's authorize URL and sets a state cookie.
    const start = await api.handler(
      new Request(url("/v1/auth/sign-in/social"), {
        method: "POST",
        headers: { "content-type": "application/json", origin: WEB_ORIGIN },
        body: JSON.stringify({ provider: "dev", callbackURL: "/" }),
      }),
    );
    expect(start.status).toBe(200);
    const { url: authorizeUrl } = (await start.json()) as { url: string };
    const stateCookies = start.headers
      .getSetCookie()
      .map((c) => c.split(";")[0])
      .join("; ");

    // 2. The provider redirects back to our callback with a code.
    const authorize = await fetch(authorizeUrl, { redirect: "manual" });
    expect(authorize.status).toBe(302);
    const callbackUrl = new URL(authorize.headers.get("location")!);
    expect(callbackUrl.origin + callbackUrl.pathname).toBe(url("/v1/auth/callback/dev"));

    // 3. The callback exchanges the code, sets the session cookie and redirects to the app.
    const callback = await api.handler(
      new Request(callbackUrl, { headers: { cookie: stateCookies }, redirect: "manual" }),
    );
    expect(callback.status).toBe(302);
    expect(callback.headers.get("location")).toBe("/");

    const me = await api.handler(
      new Request(url("/v1/account/me"), { headers: { cookie: sessionCookie(callback) } }),
    );
    expect(me.status).toBe(200);
    expect(await me.json()).toMatchObject({ email: "oauth@example.com" });
  });
});
