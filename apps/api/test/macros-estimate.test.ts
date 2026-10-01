import type { MacroEstimateInput } from "@cauldron/shared";
import { layer } from "@effect/vitest";
import { Effect } from "effect";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { distill } from "../src/imports/distill.ts";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import { fromModelMacros, RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { DistillServices, makeOwner, WEB_ORIGIN } from "./helpers.ts";

// Macro estimates from the model: on demand from the editor, and on import
// when the source publishes no nutrition.

const ESTIMATE = { calories: 480, protein: 21.5, carbs: 52, fat: 17 };

const asked: Array<MacroEstimateInput> = [];
const fakeModel = RecipeExtractor.layerTest(
  () => Effect.succeed(emptyExtracted),
  (input) => {
    asked.push(input);
    return Effect.succeed(ESTIMATE);
  },
);

const ld = (extra: Record<string, unknown>) =>
  `<script type="application/ld+json">${JSON.stringify({
    "@context": "https://schema.org",
    "@type": "Recipe",
    name: "Bean chili",
    recipeYield: "4 servings",
    recipeIngredient: ["2 cans kidney beans", "1 onion, diced"],
    recipeInstructions: [{ "@type": "HowToStep", text: "Simmer everything." }],
    ...extra,
  })}</script>`;
const page = (head: string) => ({
  bytes: new TextEncoder().encode(`<!doctype html><html><head>${head}</head><body></body></html>`),
  contentType: "text/html; charset=utf-8",
});

const signUp = async (api: AuthApi, email: string) => {
  const before = (await api.outbox()).length;
  await api.post("/v1/auth/sign-up/email", { email, password: "correct-horse-1", name: "Cook" });
  const mail = await api.waitForOutbox(before + 1);
  return cookieOf(await api.send(api.linkIn(mail.at(-1)!)))!;
};

const caller =
  (api: AuthApi, cookie: string) => async (method: string, path: string, body?: unknown) => {
    const res = await api.send(path, {
      method,
      headers: {
        cookie,
        origin: WEB_ORIGIN,
        ...(body === undefined ? {} : { "content-type": "application/json" }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const text = await res.text();
    // oxlint-disable-next-line typescript/no-explicit-any
    return { status: res.status, body: text ? JSON.parse(text) : (null as any) };
  };

describe("with a model", () => {
  let api: AuthApi;
  let call: ReturnType<typeof caller>;

  beforeAll(async () => {
    api = makeAuthApi({}, undefined, {}, fakeModel);
    call = caller(api, await signUp(api, "ada@example.com"));
  });
  afterAll(() => api.dispose());

  it("estimates macros from ingredient lines", async () => {
    const before = asked.length;
    const res = await call("POST", "/v1/recipes/macros", {
      title: "Bean chili",
      servings: 4,
      ingredients: ["2 cans kidney beans", "1 onion, diced"],
    });
    expect(res.status).toBe(200);
    expect(res.body).toEqual(ESTIMATE);
    expect(asked.slice(before)).toEqual([
      { title: "Bean chili", servings: 4, ingredients: ["2 cans kidney beans", "1 onion, diced"] },
    ]);
  });

  it("refuses an estimate without ingredients", async () => {
    const res = await call("POST", "/v1/recipes/macros", {
      title: null,
      servings: null,
      ingredients: [],
    });
    expect(res.status).toBe(400);
  });
});

const pages = {
  "https://cook.example/chili": page(ld({})),
  "https://cook.example/chili-facts": page(
    ld({ nutrition: { calories: "390 kcal", proteinContent: "18 g" } }),
  ),
};

layer(DistillServices(pages, fakeModel))("estimating on import", (it) => {
  it.effect("fills a draft's missing macros with an estimate, flagged to check", () =>
    Effect.gen(function* () {
      const { draft } = yield* distill({ url: "https://cook.example/chili" }, yield* makeOwner());
      expect(draft.macros).toEqual(ESTIMATE);
      expect(draft.unsure).toContain("macros");
      expect(asked.at(-1)).toMatchObject({ servings: 4, title: "Bean chili" });
    }),
  );

  it.effect("keeps the page's own nutrition and doesn't ask the model", () =>
    Effect.gen(function* () {
      const before = asked.length;
      const { draft } = yield* distill(
        { url: "https://cook.example/chili-facts" },
        yield* makeOwner(),
      );
      expect(draft.macros).toEqual({ calories: 390, protein: 18, carbs: null, fat: null });
      expect(draft.unsure).not.toContain("macros");
      expect(asked.length).toBe(before);
    }),
  );
});

layer(DistillServices(pages))("estimating on import without a model", (it) => {
  it.effect("leaves the macros blank", () =>
    Effect.gen(function* () {
      const { draft } = yield* distill({ url: "https://cook.example/chili" }, yield* makeOwner());
      expect(draft.macros).toBeUndefined();
      expect(draft.unsure).not.toContain("macros");
    }),
  );
});

describe("without a model", () => {
  let api: AuthApi;
  let call: ReturnType<typeof caller>;

  beforeAll(async () => {
    api = makeAuthApi();
    call = caller(api, await signUp(api, "bob@example.com"));
  });
  afterAll(() => api.dispose());

  it("says estimating isn't set up", async () => {
    const res = await call("POST", "/v1/recipes/macros", {
      title: null,
      servings: 2,
      ingredients: ["1 cup rice"],
    });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe("unavailable");
  });
});

describe("fromModelMacros", () => {
  it("rounds, and drops negative or absurd values", () => {
    expect(
      fromModelMacros({ servings: 4, calories: 512.6, protein: 21.26, carbs: -3, fat: 99999 }),
    ).toEqual({ calories: 513, protein: 21.5, carbs: null, fat: null });
  });
});
