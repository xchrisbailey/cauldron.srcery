import { compileErrors, validate } from "@readme/openapi-parser";
import { Api } from "@cauldron/api-spec";
import { afterAll, describe, expect, it } from "vite-plus/test";
import { makeTestApi, url } from "./helpers.ts";

describe("OpenAPI document", () => {
  const api = makeTestApi();
  afterAll(() => api.dispose());

  const fetchSpec = async () => {
    const res = await api.handler(new Request(url("/v1/openapi.json")));
    expect(res.status).toBe(200);
    return (await res.json()) as { paths: Record<string, Record<string, unknown>> };
  };

  it("is a valid OpenAPI 3.1 document", async () => {
    const spec = structuredClone(await fetchSpec()) as unknown as Parameters<typeof validate>[0];
    const result = await validate(spec);
    expect(result.valid, result.valid ? "" : compileErrors(result)).toBe(true);
  });

  it("lists every endpoint in the API definition", async () => {
    const spec = await fetchSpec();
    const endpoints = Object.values(Api.groups).flatMap((group) => Object.values(group.endpoints));
    expect(endpoints.length).toBeGreaterThan(0);
    for (const endpoint of endpoints) {
      const path = endpoint.path.replace(/:(\w+)/g, "{$1}");
      expect(
        spec.paths[path]?.[endpoint.method.toLowerCase()],
        `${endpoint.method} ${path}`,
      ).toBeDefined();
    }
  });

  it("documents the recipe and tag routes with their schemas", async () => {
    const spec = await fetchSpec();
    for (const [path, method] of [
      ["/v1/recipes", "get"],
      ["/v1/recipes", "post"],
      ["/v1/recipes/search", "get"],
      ["/v1/recipes/{id}", "get"],
      ["/v1/recipes/{id}", "put"],
      ["/v1/recipes/{id}", "delete"],
      ["/v1/recipes/{id}/restore", "post"],
      ["/v1/recipes/{id}/duplicate", "post"],
      ["/v1/recipes/{id}/cooked", "post"],
      ["/v1/tags", "get"],
      ["/v1/tags/{id}", "patch"],
    ] as const) {
      const operation = spec.paths[path]?.[method] as
        | { responses: Record<string, { content?: unknown }>; requestBody?: unknown }
        | undefined;
      expect(operation, `${method} ${path}`).toBeDefined();
      expect(operation!.responses["200"]?.content, `${method} ${path} 200`).toBeDefined();
      expect(Object.keys(operation!.responses), `${method} ${path}`).toContain("401");
      if (method === "post" && path !== "/v1/recipes/{id}/restore" && !path.endsWith("duplicate")) {
        expect(operation!.requestBody, `${method} ${path} body`).toBeDefined();
      }
    }
  });

  it("documents the error shape for guarded routes", async () => {
    const spec = await fetchSpec();
    const me = spec.paths["/v1/account/me"]?.["get"] as { responses: Record<string, unknown> };
    expect(Object.keys(me.responses)).toContain("401");
  });
});
