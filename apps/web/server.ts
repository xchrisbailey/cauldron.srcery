// Production server: static assets, a same-origin /v1 proxy to the API, and
// TanStack Start SSR for everything else.
import { join, normalize, sep } from "node:path";
import type { Server } from "bun";
import { forwardHeaders } from "./forward-headers.ts";
import {
  generateNonce,
  NONCE_HEADER,
  securityHeaderOptionsFromEnv,
  withSecurityHeaders,
} from "./security-headers.ts";

const port = Number(process.env.PORT ?? 3000);
const apiOrigin = (process.env.API_ORIGIN ?? "http://localhost:3001").replace(/\/+$/, "");
// Set when a load balancer we control sits in front and appends the client IP
// to X-Forwarded-For. Otherwise client-sent forwarding headers are dropped.
const trustProxy = process.env.TRUST_PROXY === "true";
const clientDir = join(import.meta.dir, "dist", "client");

const isApiPath = (pathname: string) => pathname === "/v1" || pathname.startsWith("/v1/");

const staticFile = async (pathname: string): Promise<Response | undefined> => {
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return undefined;
  }
  if (decoded.includes("\0")) return undefined;
  const filePath = normalize(join(clientDir, decoded));
  if (!filePath.startsWith(clientDir + sep)) return undefined;
  const file = Bun.file(filePath);
  if (!(await file.exists())) return undefined;
  const headers = new Headers({ "content-type": file.type });
  if (pathname.startsWith("/assets/")) {
    headers.set("cache-control", "public, max-age=31536000, immutable");
  }
  return new Response(file, { headers });
};

const proxy = (request: Request, url: URL, server: Server<unknown>): Promise<Response> =>
  fetch(apiOrigin + url.pathname + url.search, {
    method: request.method,
    headers: forwardHeaders(request.headers, server.requestIP(request)?.address, trustProxy),
    body: request.body,
    redirect: "manual",
    decompress: false,
    signal: AbortSignal.timeout(30_000),
    // Keep the body streaming for uploads.
    duplex: "half",
  } as RequestInit);

if (import.meta.main) {
  // Built output, resolved at runtime so typechecking works before a build.
  const entry = join(import.meta.dir, "dist", "server", "server.js");
  const start = (await import(entry)) as {
    default: { fetch: (request: Request) => Response | Promise<Response> };
  };

  // Every response gets the security headers. Only SSR needs the nonce, which
  // the router puts on every inline script it emits.
  const respond = async (
    request: Request,
    server: Server<unknown>,
    nonce: string,
  ): Promise<Response> => {
    const url = new URL(request.url);
    if (isApiPath(url.pathname)) {
      try {
        return await proxy(request, url, server);
      } catch {
        return Response.json(
          { error: { code: "bad_gateway", message: "Cauldron can't reach its API right now." } },
          { status: 502 },
        );
      }
    }
    if (request.method === "GET" || request.method === "HEAD") {
      const file = await staticFile(url.pathname);
      if (file) return file;
    }
    // Never trust a client-sent nonce: this overwrites it for the page render.
    const headers = new Headers(request.headers);
    headers.set(NONCE_HEADER, nonce);
    return start.default.fetch(new Request(request, { headers }));
  };

  Bun.serve({
    port,
    async fetch(request, server) {
      const nonce = generateNonce();
      const proxied = isApiPath(new URL(request.url).pathname);
      const options = { ...securityHeaderOptionsFromEnv(process.env, nonce), csp: !proxied };
      try {
        return withSecurityHeaders(await respond(request, server, nonce), options);
      } catch (error) {
        // A failed render still answers with the headers, not Bun's bare 500.
        console.error(error);
        return withSecurityHeaders(
          Response.json(
            { error: { code: "internal", message: "Something went wrong on our side." } },
            { status: 500 },
          ),
          options,
        );
      }
    },
  });
  console.log(`web listening on :${port}, proxying /v1 to ${apiOrigin}`);
}
