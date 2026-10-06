import { afterAll, describe, expect, it } from "vite-plus/test";
import { AUTH_ACCOUNT_RATE_LIMIT, AUTH_RATE_LIMIT } from "../src/http/AuthRoute.ts";
import { cookieOf, makeAuthApi } from "./auth-helpers.ts";

const signIn = { email: "nobody@example.test", password: "wrong-password" };

describe("auth rate limit", () => {
  describe("with TRUST_PROXY off", () => {
    const api = makeAuthApi({ authRateLimit: true });
    afterAll(() => api.dispose());

    it("answers the sixth sign-in in a minute with 429 in Better Auth's error shape", async () => {
      for (let i = 0; i < AUTH_RATE_LIMIT.limit; i++) {
        expect((await api.post("/v1/auth/sign-in/email", signIn)).status).toBe(401);
      }
      const res = await api.post("/v1/auth/sign-in/email", signIn);
      expect(res.status).toBe(429);
      expect(Number(res.headers.get("retry-after"))).toBeGreaterThanOrEqual(1);
      expect(await res.json()).toMatchObject({ code: "TOO_MANY_REQUESTS" });
    });

    it("ignores client-supplied x-client-ip and x-forwarded-for", async () => {
      // No socket in a web handler, so every request shares the "unknown" address.
      for (let i = 0; i < AUTH_RATE_LIMIT.limit; i++) {
        await api.post(
          "/v1/auth/request-password-reset",
          { email: `a${i}@example.test` },
          {
            "x-client-ip": `8.8.8.${i}`,
            "x-forwarded-for": `9.9.9.${i}`,
          },
        );
      }
      const res = await api.post(
        "/v1/auth/request-password-reset",
        { email: "z@example.test" },
        { "x-client-ip": "8.8.8.99", "x-forwarded-for": "9.9.9.99" },
      );
      expect(res.status).toBe(429);
    });

    it("keeps a separate budget per endpoint and leaves other auth routes alone", async () => {
      expect((await api.post("/v1/auth/sign-up/email", { ...signIn, name: "N" })).status).not.toBe(
        429,
      );
      for (let i = 0; i < AUTH_RATE_LIMIT.limit + 2; i++) {
        expect((await api.send("/v1/auth/get-session")).status).toBe(200);
      }
    });

    it("limits a password check behind a session the same way", async () => {
      for (let i = 0; i < AUTH_RATE_LIMIT.limit; i++) {
        expect(
          (await api.post("/v1/auth/change-password", { currentPassword: "x", newPassword: "y" }))
            .status,
        ).toBe(401);
      }
      const res = await api.post("/v1/auth/change-password", {
        currentPassword: "x",
        newPassword: "y",
      });
      expect(res.status).toBe(429);
    });

    it("can't be dodged with a trailing slash", async () => {
      for (let i = 0; i < AUTH_RATE_LIMIT.limit; i++) {
        await api.post("/v1/auth/send-verification-email/", { email: "x@example.test" });
      }
      expect(
        (await api.post("/v1/auth/send-verification-email", { email: "x@example.test" })).status,
      ).toBe(429);
    });
  });

  describe("with TRUST_PROXY on", () => {
    const api = makeAuthApi({ authRateLimit: true, trustProxy: true });
    afterAll(() => api.dispose());
    const from = (ip: string) => ({ "x-client-ip": ip });

    it("keys the limit on x-client-ip", async () => {
      for (let i = 0; i < AUTH_RATE_LIMIT.limit; i++) {
        expect((await api.post("/v1/auth/sign-in/email", signIn, from("1.1.1.1"))).status).toBe(
          401,
        );
      }
      expect((await api.post("/v1/auth/sign-in/email", signIn, from("1.1.1.1"))).status).toBe(429);
      expect((await api.post("/v1/auth/sign-in/email", signIn, from("2.2.2.2"))).status).toBe(401);
    });
  });

  describe("per-account budget", () => {
    const api = makeAuthApi({ authRateLimit: true, trustProxy: true });
    afterAll(() => api.dispose());
    const from = (ip: string) => ({ "x-client-ip": ip });
    const attempt = (email: string, ip: string) =>
      api.post("/v1/auth/sign-in/email", { email, password: "wrong-password" }, from(ip));

    it("limits one account across rotating addresses, and leaves other accounts alone", async () => {
      for (let i = 0; i < AUTH_ACCOUNT_RATE_LIMIT.limit; i++) {
        expect((await attempt("victim@example.test", `10.0.0.${i}`)).status).toBe(401);
      }
      const res = await attempt("victim@example.test", "10.0.1.1");
      expect(res.status).toBe(429);
      expect(Number(res.headers.get("retry-after"))).toBeGreaterThanOrEqual(1);
      expect(await res.json()).toMatchObject({ code: "TOO_MANY_REQUESTS" });
      expect((await attempt("other@example.test", "10.0.1.1")).status).toBe(401);
    });

    it("shares one budget across email case and whitespace variants", async () => {
      const variants = [
        "Case@Example.test",
        " case@example.test",
        "CASE@EXAMPLE.TEST ",
        "case@example.test",
      ];
      for (let i = 0; i < AUTH_ACCOUNT_RATE_LIMIT.limit; i++) {
        // Better Auth itself may answer a padded email with 400; what matters is no 429 yet.
        expect((await attempt(variants[i % variants.length]!, `10.1.0.${i}`)).status).not.toBe(429);
      }
      expect((await attempt("  CaSe@example.test", "10.1.1.1")).status).toBe(429);
    });

    it("doesn't spend the account budget on a blocked address", async () => {
      for (let i = 0; i < AUTH_RATE_LIMIT.limit; i++) {
        await attempt("burn@example.test", "10.2.0.1");
      }
      // The address is now blocked; these must not count against the account.
      for (let i = 0; i < 20; i++) {
        expect((await attempt("burn@example.test", "10.2.0.1")).status).toBe(429);
      }
      expect((await attempt("burn@example.test", "10.2.0.2")).status).toBe(401);
    });

    it("lets a correct sign-in through with the limiter on", async () => {
      const email = "good@example.test";
      const password = "correct-horse-1";
      await api.post(
        "/v1/auth/sign-up/email",
        { email, password, name: "Good", callbackURL: "/" },
        from("10.3.0.1"),
      );
      const [mail] = (await api.waitForOutbox(1)).filter((m) => m.to === email);
      const verify = await api.send(api.linkIn(mail!));
      expect(cookieOf(verify)).toBeTruthy();
      const res = await api.post("/v1/auth/sign-in/email", { email, password }, from("10.3.0.2"));
      expect(res.status).toBe(200);
      expect(cookieOf(res)).toBeTruthy();
    });

    it("limits delete-user per address like the others", async () => {
      for (let i = 0; i < AUTH_RATE_LIMIT.limit; i++) {
        expect((await api.post("/v1/auth/delete-user", {}, from("10.4.0.1"))).status).toBe(401);
      }
      expect((await api.post("/v1/auth/delete-user", {}, from("10.4.0.1"))).status).toBe(429);
    });

    it("limits a password check per session credential across addresses", async () => {
      const cookie = { cookie: "better-auth.session_token=made-up.value" };
      for (let i = 0; i < AUTH_ACCOUNT_RATE_LIMIT.limit; i++) {
        const res = await api.post(
          "/v1/auth/verify-password",
          { password: "x" },
          { ...cookie, ...from(`10.5.${Math.floor(i / 4)}.${i % 4}`) },
        );
        expect(res.status).toBe(401);
      }
      expect(
        (
          await api.post(
            "/v1/auth/verify-password",
            { password: "x" },
            { ...cookie, ...from("10.5.9.9") },
          )
        ).status,
      ).toBe(429);
    });

    it("passes a non-JSON, empty or email-less sign-in body on to Better Auth", async () => {
      for (const body of ["not json", "", "[1,2]", JSON.stringify({ password: "x" })]) {
        const res = await api.send("/v1/auth/sign-in/email", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            origin: "http://localhost:3000",
            ...from("10.6.0.1"),
          },
          body: body === "" ? null : body,
        });
        expect(res.status).toBeLessThan(500);
        expect(res.status).not.toBe(429);
      }
    });
  });

  describe("when off (development and tests by default)", () => {
    const api = makeAuthApi();
    afterAll(() => api.dispose());

    it("doesn't limit", async () => {
      for (let i = 0; i < AUTH_RATE_LIMIT.limit + 2; i++) {
        expect((await api.post("/v1/auth/sign-in/email", signIn)).status).toBe(401);
      }
    });
  });
});
