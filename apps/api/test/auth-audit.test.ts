import { schema } from "@cauldron/db";
import { Effect, Logger, References } from "effect";
import { OAuth2Server } from "oauth2-mock-server";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { Db } from "../src/Db.ts";
import { cookieOf, makeAuthApi } from "./auth-helpers.ts";

const EMAIL = "audit@example.com";
const NAME = "Audit Person";
const PASSWORD = "correct-horse-1";
const NEW_PASSWORD = "battery-staple-2";
const RESET_PASSWORD = "brand-new-pass-3";

type Line = { message: string; annotations: Record<string, unknown> };

describe("auth audit log", () => {
  const oidc = new OAuth2Server();
  const lines: Array<Line> = [];
  const collector = Logger.make<unknown, void>(({ message, fiber }) => {
    lines.push({
      message: String(message),
      annotations: { ...fiber.getRef(References.CurrentLogAnnotations) },
    });
  });
  let api: ReturnType<typeof makeAuthApi>;

  beforeAll(async () => {
    await oidc.issuer.keys.generate("RS256");
    await oidc.start(0, "127.0.0.1");
    oidc.service.on("beforeUserinfo", (res) => {
      res.body = { sub: "oidc-audit", email: EMAIL, name: NAME, email_verified: true };
    });
    oidc.service.on("beforeTokenSigning", (token) => {
      token.payload.email = EMAIL;
      token.payload.name = NAME;
      token.payload.email_verified = true;
    });
    api = makeAuthApi(
      {
        trustProxy: true,
        devOAuth: {
          providerId: "dev",
          clientId: "cauldron-dev",
          clientSecret: "cauldron-dev-secret",
          discoveryUrl: `${oidc.issuer.url}/.well-known/openid-configuration`,
        },
      },
      undefined,
      {},
      undefined,
      [collector],
    );
  });

  afterAll(async () => {
    await api.dispose();
    await oidc.stop();
  });

  const events = (name: string) => lines.filter((l) => l.annotations.event === name);

  /** Hooks log from a forked fiber, so wait for the line to land. */
  const waitForEvent = async (name: string, count: number) => {
    for (let i = 0; i < 200 && events(name).length < count; i++) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    expect(events(name)).toHaveLength(count);
    return events(name);
  };

  it("logs one structured line per security event, with no secrets", async () => {
    const ip = { "x-client-ip": "203.0.113.7" };

    // Sign up and verify by email link (the verification signs in).
    await api.post("/v1/auth/sign-up/email", {
      email: EMAIL,
      password: PASSWORD,
      name: NAME,
      callbackURL: "/",
    });
    const [mail] = await api.waitForOutbox(1);
    const verifyToken = new URL(api.linkIn(mail!), "http://x").searchParams.get("token")!;
    const verify = await api.send(api.linkIn(mail!), { headers: ip });
    const verified = cookieOf(verify)!;
    expect(verified).toBeTruthy();

    const [user] = await api.run(
      Effect.gen(function* () {
        const db = yield* Db;
        return yield* db.use((d) => d.select({ id: schema.user.id }).from(schema.user));
      }),
    );
    const userId = user!.id;

    const linked = await waitForEvent("account.linked", 1);
    expect(linked[0]!.annotations).toMatchObject({ userId, providerId: "credential" });
    const created = await waitForEvent("session.created", 1);
    expect(created[0]!.annotations).toMatchObject({ userId, ipAddress: "203.0.113.7" });

    // Sign in.
    const signIn = await api.post(
      "/v1/auth/sign-in/email",
      { email: EMAIL, password: PASSWORD },
      ip,
    );
    expect(signIn.status).toBe(200);
    const cookie = cookieOf(signIn)!;
    const bearer = signIn.headers.get("set-auth-token")!;
    await waitForEvent("session.created", 2);

    // Link a provider through the OIDC mock (its email is verified, so it links here).
    const start = await api.post("/v1/auth/sign-in/social", { provider: "dev", callbackURL: "/" });
    const { url: authorizeUrl } = (await start.json()) as { url: string };
    const stateCookies = start.headers
      .getSetCookie()
      .map((c) => c.split(";")[0])
      .join("; ");
    const authorize = await fetch(authorizeUrl, { redirect: "manual" });
    const callbackUrl = new URL(authorize.headers.get("location")!);
    const callback = await api.send(callbackUrl.pathname + callbackUrl.search, {
      headers: { cookie: stateCookies },
    });
    expect(callback.status).toBe(302);
    const both = await waitForEvent("account.linked", 2);
    expect(both[1]!.annotations).toMatchObject({ userId, providerId: "dev" });

    // Change the password.
    const change = await api.post(
      "/v1/auth/change-password",
      { currentPassword: PASSWORD, newPassword: NEW_PASSWORD },
      { cookie },
    );
    expect(change.status).toBe(200);
    const changed = await waitForEvent("password.changed", 1);
    expect(changed[0]!.annotations).toMatchObject({ userId });

    // Sign out.
    const out = await api.post("/v1/auth/sign-out", {}, { cookie });
    expect(out.status).toBe(200);
    const ended = await waitForEvent("session.deleted", 1);
    expect(ended[0]!.annotations).toMatchObject({ userId });

    // Reset the password by email link.
    await api.post("/v1/auth/request-password-reset", { email: EMAIL, redirectTo: "/reset" });
    const [, resetMail] = await api.waitForOutbox(2);
    const link = await api.send(api.linkIn(resetMail!));
    const resetToken = new URL(link.headers.get("location")!, "http://x").searchParams.get(
      "token",
    )!;
    const reset = await api.post("/v1/auth/reset-password", {
      newPassword: RESET_PASSWORD,
      token: resetToken,
    });
    expect(reset.status).toBe(200);
    const resets = await waitForEvent("password.changed", 2);
    expect(resets[1]!.annotations).toMatchObject({ userId });

    // Signing in again through the provider updates its account row, not a password.
    const again = await api.post("/v1/auth/sign-in/social", { provider: "dev", callbackURL: "/" });
    const againAuthorize = await fetch(((await again.json()) as { url: string }).url, {
      redirect: "manual",
    });
    const againCallback = new URL(againAuthorize.headers.get("location")!);
    await api.send(againCallback.pathname + againCallback.search, {
      headers: {
        cookie: again.headers
          .getSetCookie()
          .map((c) => c.split(";")[0])
          .join("; "),
      },
    });
    await api.settle();
    expect(events("password.changed")).toHaveLength(2);
    expect(events("account.linked")).toHaveLength(2);

    // Delete the account.
    const fresh = await api.post("/v1/auth/sign-in/email", {
      email: EMAIL,
      password: RESET_PASSWORD,
    });
    const del = await api.post(
      "/v1/auth/delete-user",
      { password: RESET_PASSWORD },
      { cookie: cookieOf(fresh)! },
    );
    expect(del.status).toBe(200);
    const deleted = await waitForEvent("user.deleted", 1);
    expect(deleted[0]!.annotations).toMatchObject({ userId });

    // Every audit line is the same plain message, and none of it holds a secret.
    await api.settle();
    for (const line of lines.filter((l) => l.annotations.event)) {
      expect(line.message).toBe("auth event");
    }
    const everything = JSON.stringify(lines);
    for (const secret of [
      EMAIL,
      NAME,
      PASSWORD,
      NEW_PASSWORD,
      RESET_PASSWORD,
      resetToken,
      verifyToken,
      bearer,
      verified.split("=")[1]!,
      cookie.split("=")[1]!,
    ]) {
      expect(everything).not.toContain(secret);
    }
  });
});
