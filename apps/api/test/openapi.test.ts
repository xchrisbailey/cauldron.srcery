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

  it("documents the error shape for guarded routes", async () => {
    const spec = await fetchSpec();
    const me = spec.paths["/v1/account/me"]?.["get"] as { responses: Record<string, unknown> };
    expect(Object.keys(me.responses)).toContain("401");
  });
});
