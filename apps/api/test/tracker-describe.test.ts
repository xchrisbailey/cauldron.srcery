import { copy, MEAL_DESCRIPTION_MAX } from "@cauldron/shared";
import { Effect } from "effect";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import { fromModelMeal, type ModelMeal, RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

// Describe it (#114): a meal in words, split into foods by the model.

const asked: Array<string> = [];
let answer: unknown = { items: [] };

const fakeModel = RecipeExtractor.layerTest(
  () => Effect.succeed(emptyExtracted),
  undefined,
  (text) => {
    asked.push(text);
    return Effect.succeed(answer);
  },
);

const signUp = async (api: AuthApi, email: string) => {
  const before = (await api.outbox()).length;
  await api.post("/v1/auth/sign-up/email", { email, password: "correct-horse-1", name: "Cook" });
  const mail = await api.waitForOutbox(before + 1);
  return cookieOf(await api.send(api.linkIn(mail.at(-1)!)))!;
};

const caller =
  (api: AuthApi, cookie: string | null) => async (method: string, path: string, body?: unknown) => {
    const res = await api.send(path, {
      method,
      headers: {
        ...(cookie === null ? {} : { cookie }),
        origin: WEB_ORIGIN,
        ...(body === undefined ? {} : { "content-type": "application/json" }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const text = await res.text();
    // oxlint-disable-next-line typescript/no-explicit-any
    return { status: res.status, body: text ? JSON.parse(text) : (null as any) };
  };

const NULLS = { calories: null, protein: null, carbs: null, fat: null };

const item = (over: Partial<ModelMeal["items"][number]> = {}): ModelMeal["items"][number] => ({
  name: "Eggs",
  amount: "2 large",
  food: true,
  calories: 140,
  protein: 12,
  carbs: 1,
  fat: 10,
  ...over,
});

describe("with a model", () => {
  let api: AuthApi;
  let call: ReturnType<typeof caller>;

  beforeAll(async () => {
    api = makeAuthApi({}, undefined, {}, fakeModel);
    call = caller(api, await signUp(api, "ada@example.com"));
  });
  afterAll(() => api.dispose());

  it("splits a meal into foods with rounded, bounded numbers", async () => {
    answer = {
      items: [
        item({ calories: 140.4, protein: 12.26, carbs: 0.9, fat: 10.74 }),
        item({
          name: "Sourdough",
          amount: "1 slice",
          calories: 120,
          protein: -2,
          carbs: 24,
          fat: 99999,
        }),
        item({
          name: "Coffee",
          amount: null,
          calories: null,
          protein: null,
          carbs: null,
          fat: null,
        }),
      ],
    };
    const before = asked.length;
    const res = await call("POST", "/v1/tracker/describe", {
      text: "  2 eggs, sourdough and black coffee \n",
    });
    expect(res.status).toBe(200);
    expect(res.body.items).toEqual([
      {
        name: "Eggs",
        amount: "2 large",
        macros: { calories: 140, protein: 12.5, carbs: 1, fat: 10.5 },
      },
      {
        name: "Sourdough",
        amount: "1 slice",
        macros: { calories: 120, protein: null, carbs: 24, fat: null },
      },
      { name: "Coffee", amount: null, macros: NULLS },
    ]);
    expect(asked.slice(before)).toEqual(["2 eggs, sourdough and black coffee"]);
  });

  it("returns null numbers for a non-food item, whatever the model said", async () => {
    answer = { items: [item({ name: "A stapler", amount: null, food: false, calories: 500 })] };
    const res = await call("POST", "/v1/tracker/describe", { text: "a stapler" });
    expect(res.status).toBe(200);
    expect(res.body.items).toEqual([{ name: "A stapler", amount: null, macros: NULLS }]);
  });

  it("fails plainly when the reply can't be read", async () => {
    answer = { items: [{ name: "Eggs" }] };
    const res = await call("POST", "/v1/tracker/describe", { text: "eggs" });
    expect(res.status).toBe(503);
    expect(res.body.error.message).toBe(copy.tracker.describe.failed.text);
  });

  it("says so when no food was found", async () => {
    answer = { items: [] };
    const res = await call("POST", "/v1/tracker/describe", { text: "hmm" });
    expect(res.status).toBe(503);
    expect(res.body.error.message).toBe(copy.tracker.describe.unreadable.text);
  });

  it("refuses empty, blank and over-long text", async () => {
    const before = asked.length;
    for (const text of ["", "   \n\t "]) {
      expect((await call("POST", "/v1/tracker/describe", { text })).status).toBe(400);
    }
    const long = await call("POST", "/v1/tracker/describe", {
      text: "a".repeat(MEAL_DESCRIPTION_MAX + 1),
    });
    expect(long.status).toBe(400);
    expect(asked.length).toBe(before);
    answer = { items: [item()] };
    const exact = await call("POST", "/v1/tracker/describe", {
      text: "a".repeat(MEAL_DESCRIPTION_MAX),
    });
    expect(exact.status).toBe(200);
  });

  it("needs a session", async () => {
    const res = await caller(api, null)("POST", "/v1/tracker/describe", { text: "eggs" });
    expect(res.status).toBe(401);
  });

  it("logs the reviewed items as separate entries in the chosen slot", async () => {
    answer = {
      items: [
        item(),
        item({
          name: "Sourdough",
          amount: "1 slice",
          calories: 120,
          protein: 4,
          carbs: 24,
          fat: 1,
        }),
      ],
    };
    const described = await call("POST", "/v1/tracker/describe", { text: "eggs and toast" });
    expect(described.status).toBe(200);

    const date = "2026-09-10";
    const logged = await call("POST", "/v1/tracker/entries/batch", {
      entries: described.body.items.map(
        (i: { name: string; amount: string | null; macros: unknown }) => ({
          date,
          slot: "lunch",
          name: i.name,
          amount: i.amount ?? undefined,
          servings: 1,
          macros: i.macros,
          source: "described",
        }),
      ),
    });
    expect(logged.status).toBe(200);

    const day = await call("GET", `/v1/tracker/day?date=${date}`);
    expect(day.status).toBe(200);
    expect(day.body.entries).toHaveLength(2);
    expect(day.body.entries).toMatchObject([
      {
        name: "Eggs",
        amount: "2 large",
        slot: "lunch",
        source: "described",
        position: 0,
        macros: { calories: 140 },
      },
      {
        name: "Sourdough",
        amount: "1 slice",
        slot: "lunch",
        source: "described",
        position: 1,
        macros: { calories: 120 },
      },
    ]);
  });
});

describe("without a model", () => {
  let api: AuthApi;
  let call: ReturnType<typeof caller>;

  beforeAll(async () => {
    api = makeAuthApi();
    call = caller(api, await signUp(api, "bob@example.com"));
  });
  afterAll(() => api.dispose());

  it("says describing isn't set up", async () => {
    const res = await call("POST", "/v1/tracker/describe", { text: "eggs" });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe("unavailable");
    expect(res.body.error.message).toBe(copy.tracker.describe.unavailable.text);
  });
});

describe("fromModelMeal", () => {
  it("drops blank names and trims names and amounts", () => {
    expect(
      fromModelMeal({
        items: [
          item({ name: "   " }),
          item({ name: "  Rice ", amount: "  1 cup " }),
          item({ name: "Salt", amount: "   " }),
        ],
      }),
    ).toMatchObject([
      { name: "Rice", amount: "1 cup" },
      { name: "Salt", amount: null },
    ]);
  });

  it("keeps at most 30 items", () => {
    const items = Array.from({ length: 40 }, (_, i) => item({ name: `Food ${i}` }));
    const out = fromModelMeal({ items });
    expect(out).toHaveLength(30);
    expect(out[0]!.name).toBe("Food 0");
    expect(out[29]!.name).toBe("Food 29");
  });

  it("nulls every number of a non-food", () => {
    expect(fromModelMeal({ items: [item({ food: false })] })[0]!.macros).toEqual(NULLS);
  });
});
