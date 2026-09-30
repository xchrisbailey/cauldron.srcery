// Production server: static assets, a same-origin /v1 proxy to the API, and
// TanStack Start SSR for everything else.
import { join, normalize, sep } from "node:path";

const port = Number(process.env.PORT ?? 3000);
const apiOrigin = (process.env.API_ORIGIN ?? "http://localhost:3001").replace(/\/+$/, "");
const clientDir = join(import.meta.dir, "dist", "client");

// Built output, resolved at runtime so typechecking works before a build.
const entry = join(import.meta.dir, "dist", "server", "server.js");
const start = (await import(entry)) as {
  default: { fetch: (request: Request) => Response | Promise<Response> };
};

const staticFile = async (pathname: string): Promise<Response | undefined> => {
  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return undefined;
  }
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

const proxy = (request: Request, url: URL): Promise<Response> => {
  const headers = new Headers(request.headers);
  headers.delete("host");
  return fetch(apiOrigin + url.pathname + url.search, {
    method: request.method,
    headers,
    body: request.body,
    redirect: "manual",
    // Keep the body streaming for uploads.
    duplex: "half",
  } as RequestInit);
};

Bun.serve({
  port,
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/v1" || url.pathname.startsWith("/v1/")) {
      try {
        return await proxy(request, url);
      } catch {
        return Response.json(
          { error: { code: "bad_gateway", message: "API unavailable" } },
          { status: 502 },
        );
      }
    }
    if (request.method === "GET" || request.method === "HEAD") {
      const file = await staticFile(url.pathname);
      if (file) return file;
    }
    return start.default.fetch(request);
  },
});

console.log(`web listening on :${port}, proxying /v1 to ${apiOrigin}`);
