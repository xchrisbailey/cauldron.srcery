import { describe, expect, it } from "vite-plus/test";
import {
  contentSecurityPolicy,
  generateNonce,
  securityHeaderOptionsFromEnv,
  withSecurityHeaders,
  type SecurityHeaderOptions,
} from "../security-headers.ts";

const options: SecurityHeaderOptions = {
  publicUrl: "https://cauldron.example",
  cspReportOnly: false,
  connectSrc: undefined,
  nonce: "abc123",
};

const html = () =>
  new Response("<html></html>", { headers: { "content-type": "text/html; charset=utf-8" } });

describe("withSecurityHeaders", () => {
  it("sets every header and an enforced CSP on an HTML response", () => {
    const res = withSecurityHeaders(html(), options);
    expect(res.headers.get("strict-transport-security")).toBe(
      "max-age=31536000; includeSubDomains",
    );
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("referrer-policy")).toBe("strict-origin-when-cross-origin");
    expect(res.headers.get("permissions-policy")).toBe(
      "camera=(), microphone=(), geolocation=(), screen-wake-lock=(self)",
    );
    expect(res.headers.get("x-frame-options")).toBe("DENY");
    const csp = res.headers.get("content-security-policy")!;
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain("script-src 'self' 'nonce-abc123'");
    expect(csp).toContain("img-src 'self' data: blob:");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("object-src 'none'");
    expect(csp.split("; ").find((d) => d.startsWith("script-src"))).not.toContain("unsafe");
    expect(res.headers.get("content-security-policy-report-only")).toBeNull();
  });

  it("sets the headers but no CSP on a static asset", async () => {
    const asset = new Response("body{}", {
      headers: {
        "content-type": "text/css",
        "cache-control": "public, max-age=31536000, immutable",
      },
    });
    const res = withSecurityHeaders(asset, options);
    expect(res.headers.get("x-content-type-options")).toBe("nosniff");
    expect(res.headers.get("content-security-policy")).toBeNull();
    expect(res.headers.get("cache-control")).toBe("public, max-age=31536000, immutable");
    expect(await res.text()).toBe("body{}");
  });

  it("keeps a proxied response's own headers, status and body", async () => {
    const upstream = Response.json(
      { error: { code: "bad_gateway" } },
      { status: 502, headers: { "set-cookie": "a=b; HttpOnly" } },
    );
    const res = withSecurityHeaders(upstream, options);
    expect(res.status).toBe(502);
    expect(res.headers.get("set-cookie")).toBe("a=b; HttpOnly");
    expect(res.headers.get("x-frame-options")).toBe("DENY");
    expect(res.headers.get("content-security-policy")).toBeNull();
    expect(await res.json()).toEqual({ error: { code: "bad_gateway" } });
  });

  it("overwrites headers the upstream already set", () => {
    const upstream = new Response("", { headers: { "x-frame-options": "SAMEORIGIN" } });
    expect(withSecurityHeaders(upstream, options).headers.get("x-frame-options")).toBe("DENY");
  });

  it("sends HSTS only when PUBLIC_URL is https", () => {
    for (const publicUrl of ["http://localhost:3000", undefined]) {
      const res = withSecurityHeaders(html(), { ...options, publicUrl });
      expect(res.headers.get("strict-transport-security")).toBeNull();
    }
  });

  it("switches the CSP to report-only", () => {
    const res = withSecurityHeaders(html(), { ...options, cspReportOnly: true });
    expect(res.headers.get("content-security-policy")).toBeNull();
    expect(res.headers.get("content-security-policy-report-only")).toContain(
      "script-src 'self' 'nonce-abc123'",
    );
  });
});

describe("contentSecurityPolicy", () => {
  it("adds extra origins to connect-src and img-src", () => {
    const csp = contentSecurityPolicy({
      ...options,
      connectSrc: "https://s3.example.com, https://b.example.com",
    });
    expect(csp).toContain("connect-src 'self' https://s3.example.com https://b.example.com");
    expect(csp).toContain(
      "img-src 'self' data: blob: https://s3.example.com https://b.example.com",
    );
  });

  it("ignores entries that could inject directives", () => {
    const csp = contentSecurityPolicy({
      ...options,
      connectSrc: "https://ok.example;script-src 'unsafe-eval' *",
    });
    expect(csp).not.toContain("unsafe-eval");
    expect(csp).toContain("connect-src 'self' *");
  });
});

describe("helpers", () => {
  it("reads the options from the environment", () => {
    expect(
      securityHeaderOptionsFromEnv(
        {
          PUBLIC_URL: "https://x.test",
          CSP_REPORT_ONLY: "true",
          CSP_CONNECT_SRC: "https://s3.test",
        },
        "n",
      ),
    ).toEqual({
      publicUrl: "https://x.test",
      cspReportOnly: true,
      connectSrc: "https://s3.test",
      nonce: "n",
    });
    expect(securityHeaderOptionsFromEnv({}, "n").cspReportOnly).toBe(false);
  });

  it("generates a fresh nonce each time", () => {
    expect(generateNonce()).not.toBe(generateNonce());
    expect(generateNonce()).toMatch(/^[A-Za-z0-9+/]+=*$/);
  });
});
