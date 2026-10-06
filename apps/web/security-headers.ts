// Security headers for every response the web container sends. Pure, so it is
// tested without Bun.serve; server.ts feeds it the environment and a nonce.

export interface SecurityHeaderOptions {
  /** PUBLIC_URL; HSTS is only sent when it is https. */
  readonly publicUrl: string | undefined;
  /** Send the CSP as Content-Security-Policy-Report-Only (for a first deploy). */
  readonly cspReportOnly: boolean;
  /** CSP_CONNECT_SRC: extra origins (space or comma separated), e.g. a direct-to-S3 upload origin. */
  readonly connectSrc: string | undefined;
  /** Per-request nonce allowed for inline scripts. */
  readonly nonce: string | undefined;
}

/** Request header that carries the nonce into the Start handler; server.ts always overwrites it. */
export const NONCE_HEADER = "x-csp-nonce";

export const securityHeaderOptionsFromEnv = (
  env: Record<string, string | undefined>,
  nonce: string | undefined,
): SecurityHeaderOptions => ({
  publicUrl: env.PUBLIC_URL,
  cspReportOnly: env.CSP_REPORT_ONLY === "true",
  connectSrc: env.CSP_CONNECT_SRC,
  nonce,
});

export const generateNonce = (): string =>
  btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));

const origins = (value: string | undefined): string[] =>
  (value ?? "")
    .split(/[\s,]+/)
    .filter(Boolean)
    // Anything that could add a directive or a keyword is not an origin.
    .filter((origin) => !/[;'"]/.test(origin));

export const contentSecurityPolicy = (options: SecurityHeaderOptions): string => {
  const extras = origins(options.connectSrc);
  const scriptSrc = ["'self'", ...(options.nonce ? [`'nonce-${options.nonce}'`] : [])];
  return [
    "default-src 'self'",
    `script-src ${scriptSrc.join(" ")}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src ${["'self'", "data:", "blob:", ...extras].join(" ")}`,
    `connect-src ${["'self'", ...extras].join(" ")}`,
    "font-src 'self'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
  ].join("; ");
};

const apply = (headers: Headers, options: SecurityHeaderOptions): void => {
  if (options.publicUrl?.startsWith("https://")) {
    headers.set("strict-transport-security", "max-age=31536000; includeSubDomains");
  }
  headers.set("x-content-type-options", "nosniff");
  headers.set("referrer-policy", "strict-origin-when-cross-origin");
  headers.set(
    "permissions-policy",
    "camera=(), microphone=(), geolocation=(), screen-wake-lock=(self)",
  );
  headers.set("x-frame-options", "DENY");
  if (headers.get("content-type")?.toLowerCase().startsWith("text/html")) {
    headers.set(
      options.cspReportOnly ? "content-security-policy-report-only" : "content-security-policy",
      contentSecurityPolicy(options),
    );
  }
};

/**
 * The response with the security headers set, overwriting any the upstream
 * sent. Our own responses are changed in place, so a static file stays a file.
 * A proxied response's headers are read-only, so it is rebuilt around the same
 * body, which keeps streaming.
 */
export const withSecurityHeaders = (
  response: Response,
  options: SecurityHeaderOptions,
): Response => {
  try {
    apply(response.headers, options);
    return response;
  } catch {
    const headers = new Headers(response.headers);
    apply(headers, options);
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  }
};
