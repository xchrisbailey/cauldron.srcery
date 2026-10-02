import { parseIngredientLine, TRACKER_LIMITS, type RecipeInput } from "@cauldron/shared";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

const PASSWORD = "correct-horse-1";

let api: AuthApi;

const signUpVerified = async (email: string) => {
  const before = (await api.outbox()).length;
  await api.post("/v1/auth/sign-up/email", { email, password: PASSWORD, name: "Cook" });
  const sent = (await api.waitForOutbox(before + 1)).slice(before).filter((m) => m.to === email);
  const cookie = cookieOf(await api.send(api.linkIn(sent[0]!)));
  if (!cookie) throw new Error("verification didn't sign in");
  return cookie;
};

beforeAll(() => {
  api = makeAuthApi();
});
afterAll(() => api.dispose());

interface Res<T = any> {
  readonly status: number;
  readonly body: T;
}

const call = async (cookie: string, method: string, path: string, body?: unknown): Promise<Res> => {
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
  return { status: res.status, body: text ? JSON.parse(text) : null };
};

const lines = (...raw: ReadonlyArray<string>) =>
  raw.map((line) => ({ ...parseIngredientLine(line), section: null }));

const recipeInput = (): RecipeInput => ({
  title: "Weeknight dal",
  description: null,
  servings: 4,
  prepMinutes: 10,
  cookMinutes: 30,
  totalMinutes: 40,
  sourcePlatform: "manual",
  sourceUrl: null,
  sourceAuthor: null,
  notes: null,
  photoKey: null,
  tags: [],
  ingredients: lines("1 cup red lentils"),
  steps: [{ section: null, text: "Simmer.", timerSeconds: null }],
  macros: { calories: 300, protein: 20, carbs: 40, fat: 5 },
});

const createRecipe = async (cookie: string) => {
  const res = await call(cookie, "POST", "/v1/recipes", recipeInput());
  expect(res.status).toBe(200);
  return res.body;
};

const MACROS = { calories: 200, protein: 10, carbs: 25, fat: 5 };

const addDays = (date: string, n: number) => {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
const TODAY = new Date().toISOString().slice(0, 10);
const ago = (n: number) => addDays(TODAY, -n);

const log = async (cookie: string, body: Record<string, unknown>) => {
  const res = await call(cookie, "POST", "/v1/tracker/entries", body);
  expect(res.status).toBe(200);
  return res.body;
};

const manual = (name: string, date: string, extra: Record<string, unknown> = {}) => ({
  date,
  slot: "breakfast",
  name,
  servings: 1,
  macros: MACROS,
  source: "manual",
  ...extra,
});

const quick = async (cookie: string) => {
  const res = await call(cookie, "GET", "/v1/tracker/quick");
  expect(res.status).toBe(200);
  return res.body;
};

const dayOf = async (cookie: string, date: string) => {
  const res = await call(cookie, "GET", `/v1/tracker/day?date=${date}`);
  expect(res.status).toBe(200);
  return res.body;
};

let n = 0;
const freshUser = () => signUpVerified(`quick${++n}@example.com`);

describe("tracker recents and favourites", () => {
  it("requires a session", async () => {
    expect((await api.send("/v1/tracker/quick")).status).toBe(401);
    const copy = await api.send("/v1/tracker/copy", {
      method: "POST",
      headers: { origin: WEB_ORIGIN, "content-type": "application/json" },
      body: JSON.stringify({ from: "2026-06-01", to: "2026-06-02" }),
    });
    expect(copy.status).toBe(401);
  });

  it("starts empty", async () => {
    const u = await freshUser();
    expect(await quick(u)).toEqual({ favourites: [], recents: [] });
  });

  it("groups recents, ordered by how often then how recently, as last logged", async () => {
    const u = await freshUser();
    await log(u, manual("Oats", ago(5), { amount: "1 bowl", servings: 1 }));
    await log(u, manual("oats", ago(3), { amount: "1 BOWL", servings: 1 }));
    const last = await log(
      u,
      manual("Oats", ago(1), {
        amount: "1 bowl",
        servings: 2,
        macros: { calories: 400, protein: 20, carbs: 50, fat: 10 },
      }),
    );
    await log(u, manual("Toast", ago(2), { amount: "2 slices" }));
    await log(u, manual("Egg", ago(0), { slot: "lunch" }));
    await log(u, manual("Oats", ago(1), { amount: "2 bowls" })); // different amount, own group

    const { favourites, recents } = await quick(u);
    expect(favourites).toEqual([]);
    expect(recents.map((r: any) => r.food.name)).toEqual(["Oats", "Egg", "Oats", "Toast"]);
    expect(recents[0]).toMatchObject({
      count: 3,
      lastLoggedOn: ago(1),
      lastEntryId: last.id,
      food: {
        name: "Oats",
        amount: "1 bowl",
        servings: 2,
        macros: { calories: 400, protein: 20, carbs: 50, fat: 10 },
        source: "manual",
        recipeId: null,
      },
    });
    // Ties on count break to the most recent.
    expect(recents[1].lastLoggedOn).toBe(ago(0));
    expect(recents[2].food.amount).toBe("2 bowls");
    expect(recents[3].lastLoggedOn).toBe(ago(2));
  });

  it("gives back exactly the input to log a repeat breakfast", async () => {
    const u = await freshUser();
    const recipe = await createRecipe(u);
    await log(u, {
      date: ago(1),
      slot: "breakfast",
      servings: 1.5,
      source: "recipe",
      recipeId: recipe.id,
    });
    await log(u, manual("Porridge", ago(2), { amount: "1 bowl", servings: 0.5 }));

    const { recents } = await quick(u);
    expect(recents).toHaveLength(2);
    for (const r of recents) {
      const again = await log(u, { date: TODAY, slot: "breakfast", ...r.food });
      expect(again).toMatchObject(r.food);
    }
    const recipeFood = recents.find((r: any) => r.food.recipeId === recipe.id).food;
    expect(recipeFood).toMatchObject({
      name: "Weeknight dal",
      servings: 1.5,
      source: "recipe",
      macros: { calories: 300, protein: 20, carbs: 40, fat: 5 },
    });
  });

  it("groups recipe entries by recipe whatever they are called", async () => {
    const u = await freshUser();
    const recipe = await createRecipe(u);
    const entry = { slot: "dinner", servings: 1, source: "recipe", recipeId: recipe.id };
    await log(u, { ...entry, date: ago(2) });
    await log(u, { ...entry, date: ago(1), name: "Dal, my way" });
    const { recents } = await quick(u);
    expect(recents).toHaveLength(1);
    expect(recents[0]).toMatchObject({ count: 2, food: { name: "Dal, my way" } });
  });

  it("ignores entries older than 60 days", async () => {
    const u = await freshUser();
    await log(u, manual("Ancient", ago(61)));
    await log(u, manual("Edge", ago(60)));
    expect((await quick(u)).recents.map((r: any) => r.food.name)).toEqual(["Edge"]);
  });

  it("returns at most 30 recents", async () => {
    const u = await freshUser();
    for (let i = 0; i < 35; i++) {
      await log(u, manual(`Food ${i}`, ago(1), { slot: i % 2 ? "lunch" : "dinner" }));
    }
    expect((await quick(u)).recents).toHaveLength(30);
  });

  it("stars an entry as logged, keeps starred foods out of recents, and doesn't duplicate", async () => {
    const u = await freshUser();
    const first = await log(u, manual("Smoothie", ago(3), { amount: "1 glass" }));
    const second = await log(
      u,
      manual("Smoothie", ago(1), {
        amount: "1 glass",
        servings: 2,
        macros: { calories: 500, protein: 30, carbs: 60, fat: 8 },
      }),
    );
    await log(u, manual("Toast", ago(1)));

    const star = await call(u, "POST", "/v1/tracker/favourites", { entryId: first.id });
    expect(star.status).toBe(200);
    expect(star.body.food).toMatchObject({ name: "Smoothie", amount: "1 glass", servings: 1 });

    const again = await call(u, "POST", "/v1/tracker/favourites", { entryId: second.id });
    expect(again.status).toBe(200);
    expect(again.body.id).toBe(star.body.id);
    expect(again.body.food).toMatchObject({
      servings: 2,
      macros: { calories: 500, protein: 30, carbs: 60, fat: 8 },
    });

    const { favourites, recents } = await quick(u);
    expect(favourites).toHaveLength(1);
    expect(favourites[0].id).toBe(star.body.id);
    expect(recents.map((r: any) => r.food.name)).toEqual(["Toast"]);
  });

  it("lists favourites by name regardless of case", async () => {
    const u = await freshUser();
    for (const name of ["banana", "Apple", "cherry"]) {
      const e = await log(u, manual(name, ago(1)));
      expect((await call(u, "POST", "/v1/tracker/favourites", { entryId: e.id })).status).toBe(200);
    }
    expect((await quick(u)).favourites.map((f: any) => f.food.name)).toEqual([
      "Apple",
      "banana",
      "cherry",
    ]);
  });

  it("unstars, putting the food back in recents", async () => {
    const u = await freshUser();
    const e = await log(u, manual("Yoghurt", ago(1)));
    const star = await call(u, "POST", "/v1/tracker/favourites", { entryId: e.id });
    const gone = await call(u, "DELETE", `/v1/tracker/favourites/${star.body.id}`);
    expect(gone.status).toBe(200);
    const { favourites, recents } = await quick(u);
    expect(favourites).toEqual([]);
    expect(recents.map((r: any) => r.food.name)).toEqual(["Yoghurt"]);
    const twice = await call(u, "DELETE", `/v1/tracker/favourites/${star.body.id}`);
    expect(twice.status).toBe(404);
    expect(twice.body.error.code).toBeTruthy();
  });

  it("keeps favourites and recents to their owner", async () => {
    const owner = await freshUser();
    const other = await freshUser();
    const e = await log(owner, manual("Secret snack", ago(1)));
    const star = await call(owner, "POST", "/v1/tracker/favourites", { entryId: e.id });
    const e2 = await log(owner, manual("Other snack", ago(1)));

    expect((await call(other, "POST", "/v1/tracker/favourites", { entryId: e2.id })).status).toBe(
      404,
    );
    expect((await call(other, "DELETE", `/v1/tracker/favourites/${star.body.id}`)).status).toBe(
      404,
    );
    expect(await quick(other)).toEqual({ favourites: [], recents: [] });
    expect((await quick(owner)).favourites).toHaveLength(1);
  });

  it("rejects starring an unknown or malformed entry", async () => {
    const u = await freshUser();
    const missing = await call(u, "POST", "/v1/tracker/favourites", {
      entryId: "00000000-0000-4000-8000-000000000000",
    });
    expect(missing.status).toBe(404);
    expect((await call(u, "POST", "/v1/tracker/favourites", { entryId: "nope" })).status).toBe(400);
    expect((await call(u, "DELETE", "/v1/tracker/favourites/nope")).status).toBe(400);
  });
});

describe("copy a day", () => {
  const FROM = "2026-06-01";
  const TO = "2026-06-02";

  const batch = (cookie: string, date: string, count: number, prefix: string) =>
    call(cookie, "POST", "/v1/tracker/entries/batch", {
      entries: Array.from({ length: count }, (_, i) => manual(`${prefix} ${i}`, date)),
    });

  it("copies every entry into the same slots with the same numbers", async () => {
    const u = await freshUser();
    const recipe = await createRecipe(u);
    await log(u, manual("Oats", FROM, { amount: "1 bowl", servings: 1.5 }));
    await log(u, manual("Toast", FROM));
    await log(u, {
      date: FROM,
      slot: "dinner",
      servings: 2,
      source: "recipe",
      recipeId: recipe.id,
    });
    await log(u, manual("Apple", FROM, { slot: "snack", source: "described" }));

    const res = await call(u, "POST", "/v1/tracker/copy", { from: FROM, to: TO });
    expect(res.status).toBe(200);
    expect(res.body.date).toBe(TO);
    const source = await dayOf(u, FROM);
    expect(source.entries).toHaveLength(4);
    expect(res.body.entries).toHaveLength(4);
    const strip = (e: any) => ({
      slot: e.slot,
      name: e.name,
      amount: e.amount,
      servings: e.servings,
      macros: e.macros,
      source: e.source,
      recipeId: e.recipeId,
    });
    expect(res.body.entries.map(strip)).toEqual(source.entries.map(strip));
    expect(res.body.entries.every((e: any) => e.date === TO)).toBe(true);
    expect(new Set(res.body.entries.map((e: any) => e.id)).size).toBe(4);
    expect(res.body.totals).toEqual(source.totals);
  });

  it("appends after what the target day already has", async () => {
    const u = await freshUser();
    await log(u, manual("Existing", TO));
    await log(u, manual("Copied", FROM));
    const res = await call(u, "POST", "/v1/tracker/copy", { from: FROM, to: TO });
    expect(res.body.entries.map((e: any) => e.name)).toEqual(["Existing", "Copied"]);
    const twice = await call(u, "POST", "/v1/tracker/copy", { from: FROM, to: TO });
    expect(twice.body.entries.map((e: any) => e.name)).toEqual(["Existing", "Copied", "Copied"]);
  });

  it("copies only one slot when asked", async () => {
    const u = await freshUser();
    await log(u, manual("Oats", FROM));
    await log(u, manual("Soup", FROM, { slot: "lunch" }));
    const res = await call(u, "POST", "/v1/tracker/copy", { from: FROM, to: TO, slot: "lunch" });
    expect(res.body.entries.map((e: any) => [e.slot, e.name])).toEqual([["lunch", "Soup"]]);
  });

  it("is a no-op for an empty day, returning the target day", async () => {
    const u = await freshUser();
    await log(u, manual("Existing", TO));
    const res = await call(u, "POST", "/v1/tracker/copy", { from: "2026-06-20", to: TO });
    expect(res.status).toBe(200);
    expect(res.body.date).toBe(TO);
    expect(res.body.entries.map((e: any) => e.name)).toEqual(["Existing"]);
    const nothing = await call(u, "POST", "/v1/tracker/copy", {
      from: "2026-06-20",
      to: "2026-06-09",
    });
    expect(nothing.body).toMatchObject({ date: "2026-06-09", entries: [] });
  });

  it("rejects copying a day onto itself and bad input", async () => {
    const u = await freshUser();
    await log(u, manual("Oats", FROM));
    const same = await call(u, "POST", "/v1/tracker/copy", { from: FROM, to: FROM });
    expect(same.status).toBe(400);
    expect(same.body.error.code).toBeTruthy();
    expect((await dayOf(u, FROM)).entries).toHaveLength(1);
    expect((await call(u, "POST", "/v1/tracker/copy", { from: "x", to: TO })).status).toBe(400);
    expect(
      (await call(u, "POST", "/v1/tracker/copy", { from: FROM, to: TO, slot: "brunch" })).status,
    ).toBe(400);
  });

  it("refuses to pass the daily limit and copies nothing", async () => {
    const u = await freshUser();
    const per = TRACKER_LIMITS.perDay;
    expect((await batch(u, FROM, 10, "src")).status).toBe(200);
    expect((await batch(u, TO, per - 5, "dst")).status).toBe(200);
    const res = await call(u, "POST", "/v1/tracker/copy", { from: FROM, to: TO });
    expect(res.status).toBe(400);
    expect((await dayOf(u, TO)).entries).toHaveLength(per - 5);
  });

  it("lets a copy fill the day to exactly the limit", async () => {
    const u = await freshUser();
    const per = TRACKER_LIMITS.perDay;
    await batch(u, FROM, 5, "src");
    await batch(u, TO, per - 5, "dst");
    const res = await call(u, "POST", "/v1/tracker/copy", { from: FROM, to: TO });
    expect(res.status).toBe(200);
    expect(res.body.entries).toHaveLength(per);
  });

  it("never copies someone else's day", async () => {
    const owner = await freshUser();
    const other = await freshUser();
    await log(owner, manual("Private", FROM));
    const res = await call(other, "POST", "/v1/tracker/copy", { from: FROM, to: TO });
    expect(res.status).toBe(200);
    expect(res.body.entries).toEqual([]);
    expect((await dayOf(owner, TO)).entries).toEqual([]);
  });
});
