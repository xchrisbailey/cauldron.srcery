import { afterAll, describe, expect, it } from "vite-plus/test";
import { AUTH_RATE_LIMIT } from "../src/http/AuthRoute.ts";
import { makeAuthApi } from "./auth-helpers.ts";

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
