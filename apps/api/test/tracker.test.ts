import { parseIngredientLine, TRACKER_LIMITS, type RecipeInput } from "@cauldron/shared";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

const PASSWORD = "correct-horse-1";

let api: AuthApi;
let ada: string;
let bob: string;

const signUpVerified = async (email: string) => {
  const before = (await api.outbox()).length;
  await api.post("/v1/auth/sign-up/email", { email, password: PASSWORD, name: "Cook" });
  const sent = (await api.waitForOutbox(before + 1)).slice(before).filter((m) => m.to === email);
  const cookie = cookieOf(await api.send(api.linkIn(sent[0]!)));
  if (!cookie) throw new Error("verification didn't sign in");
  return cookie;
};

beforeAll(async () => {
  api = makeAuthApi();
  ada = await signUpVerified("ada@example.com");
  bob = await signUpVerified("bob@example.com");
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

const recipeInput = (overrides: Partial<RecipeInput> = {}): RecipeInput => ({
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
  ...overrides,
});

const createRecipe = async (cookie: string, overrides: Partial<RecipeInput> = {}) => {
  const res = await call(cookie, "POST", "/v1/recipes", recipeInput(overrides));
  expect(res.status).toBe(200);
  return res.body;
};

const DAY = "2026-04-06";
const MACROS = { calories: 200, protein: 10, carbs: 25, fat: 5 };

const log = async (cookie: string, body: Record<string, unknown>) => {
  const res = await call(cookie, "POST", "/v1/tracker/entries", body);
  expect(res.status).toBe(200);
  return res.body;
};

const manual = (name: string, extra: Record<string, unknown> = {}) => ({
  date: DAY,
  slot: "breakfast",
  name,
  servings: 1,
  macros: MACROS,
  source: "manual",
  ...extra,
});

const dayOf = async (cookie: string, date: string) => {
  const res = await call(cookie, "GET", `/v1/tracker/day?date=${date}`);
  expect(res.status).toBe(200);
  return res.body;
};

describe("tracker", () => {
  it("requires a session", async () => {
    expect((await api.send(`/v1/tracker/day?date=${DAY}`)).status).toBe(401);
    expect((await api.send("/v1/tracker/settings")).status).toBe(401);
  });

  it("shows an empty day", async () => {
    expect(await dayOf(ada, "2030-01-01")).toEqual({
      date: "2030-01-01",
      entries: [],
      totals: { calories: 0, protein: 0, carbs: 0, fat: 0 },
      targets: null,
      weighIn: null,
    });
  });

  it("logs entries and adds up the day with targets and weigh-in", async () => {
    const date = "2026-05-01";
    const toast = await log(ada, {
      date,
      slot: "breakfast",
      name: "Toast",
      amount: "2 slices",
      servings: 2,
      macros: { calories: 100, protein: 4, carbs: 20, fat: 1.5 },
      source: "manual",
    });
    expect(toast).toMatchObject({
      date,
      slot: "breakfast",
      name: "Toast",
      amount: "2 slices",
      servings: 2,
      macros: { calories: 100, protein: 4, carbs: 20, fat: 1.5 },
      source: "manual",
      recipeId: null,
      position: 0,
    });
    // Unknown numbers count as nothing.
    const described = await log(ada, {
      date,
      slot: "lunch",
      name: "Mystery stew",
      servings: 0.5,
      macros: { calories: 400, protein: null, carbs: null, fat: 10 },
      source: "described",
    });
    expect(described.source).toBe("described");
    const jam = await log(ada, manual("Jam", { date }));
    expect(jam.position).toBe(1);

    await call(ada, "PUT", "/v1/tracker/targets", {
      calories: 2000,
      protein: 150,
      carbs: 200,
      fat: 70,
      overridden: { calories: false, protein: false, carbs: false, fat: false },
    });
    await call(ada, "PUT", `/v1/tracker/weigh-ins/${date}`, { weightKg: 70.5 });

    const day = await dayOf(ada, date);
    expect(day.entries.map((e: { name: string }) => e.name)).toEqual([
      "Toast",
      "Jam",
      "Mystery stew",
    ]);
    // Per serving times servings, summed: toast x2, jam x1, stew x0.5.
    expect(day.totals).toEqual({
      calories: 200 + 200 + 200,
      protein: 8 + 10,
      carbs: 40 + 25,
      fat: 3 + 5 + 5,
    });
    expect(day.targets).toMatchObject({ calories: 2000, checkedInOn: null });
    expect(day.weighIn).toEqual({ date, weightKg: 70.5 });
  });

  it("groups intake per day and leaves empty days out", async () => {
    await log(ada, manual("A", { date: "2026-06-01" }));
    await log(ada, manual("B", { date: "2026-06-01", slot: "dinner", servings: 2 }));
    await log(ada, manual("C", { date: "2026-06-03" }));
    const res = await call(ada, "GET", "/v1/tracker/intake?from=2026-06-01&to=2026-06-05");
    expect(res.status).toBe(200);
    expect(res.body).toEqual([
      {
        date: "2026-06-01",
        entries: 2,
        totals: { calories: 600, protein: 30, carbs: 75, fat: 15 },
      },
      { date: "2026-06-03", entries: 1, totals: { calories: 200, protein: 10, carbs: 25, fat: 5 } },
    ]);
  });

  it("copies a recipe's title and per-serving macros", async () => {
    const recipe = await createRecipe(ada, { title: "Copy me" });
    const entry = await log(ada, {
      date: "2026-07-01",
      slot: "dinner",
      servings: 1.5,
      source: "recipe",
      recipeId: recipe.id,
    });
    expect(entry).toMatchObject({
      name: "Copy me",
      servings: 1.5,
      source: "recipe",
      recipeId: recipe.id,
      macros: { calories: 300, protein: 20, carbs: 40, fat: 5 },
    });
    const named = await log(ada, {
      date: "2026-07-01",
      slot: "dinner",
      name: "Renamed",
      servings: 1,
      source: "recipe",
      recipeId: recipe.id,
    });
    expect(named.name).toBe("Renamed");
  });

  it("leaves logged entries alone when the recipe is edited or banished", async () => {
    const recipe = await createRecipe(ada, { title: "Before" });
    const date = "2026-07-02";
    const entry = await log(ada, {
      date,
      slot: "lunch",
      servings: 1,
      source: "recipe",
      recipeId: recipe.id,
    });
    const edit = await call(
      ada,
      "PUT",
      `/v1/recipes/${recipe.id}`,
      recipeInput({ title: "After", macros: { calories: 999, protein: 99, carbs: 99, fat: 99 } }),
    );
    expect(edit.status).toBe(200);
    let day = await dayOf(ada, date);
    expect(day.entries[0]).toMatchObject({
      id: entry.id,
      name: "Before",
      macros: { calories: 300, protein: 20, carbs: 40, fat: 5 },
    });
    expect(day.totals.calories).toBe(300);
    expect((await call(ada, "DELETE", `/v1/recipes/${recipe.id}`)).status).toBe(200);
    day = await dayOf(ada, date);
    expect(day.entries).toHaveLength(1);
    expect(day.entries[0]).toMatchObject({ name: "Before", macros: { calories: 300 } });
  });

  it("logs a batch in order, all or none", async () => {
    const recipe = await createRecipe(ada, { title: "Batch recipe" });
    const date = "2026-08-01";
    const good = await call(ada, "POST", "/v1/tracker/entries/batch", {
      entries: [
        manual("One", { date }),
        { date, slot: "breakfast", servings: 1, source: "recipe", recipeId: recipe.id },
      ],
    });
    expect(good.status).toBe(200);
    expect(good.body.map((e: { name: string }) => e.name)).toEqual(["One", "Batch recipe"]);
    expect(good.body.map((e: { position: number }) => e.position)).toEqual([0, 1]);

    const date2 = "2026-08-02";
    const bad = await call(ada, "POST", "/v1/tracker/entries/batch", {
      entries: [
        manual("Never", { date: date2 }),
        {
          date: date2,
          slot: "lunch",
          servings: 1,
          source: "recipe",
          recipeId: "00000000-0000-4000-8000-000000000000",
        },
      ],
    });
    expect(bad.status).toBe(400);
    expect((await dayOf(ada, date2)).entries).toEqual([]);

    const empty = await call(ada, "POST", "/v1/tracker/entries/batch", { entries: [] });
    expect(empty.status).toBe(400);
  });

  it("updates servings, slot, date and macros, and deletes", async () => {
    const date = "2026-09-01";
    await log(ada, manual("Other", { date, slot: "dinner" }));
    const entry = await log(ada, manual("Edit me", { date }));
    const servings = await call(ada, "PATCH", `/v1/tracker/entries/${entry.id}`, { servings: 3 });
    expect(servings.status).toBe(200);
    expect(servings.body).toMatchObject({ servings: 3, slot: "breakfast", position: 0 });

    const moved = await call(ada, "PATCH", `/v1/tracker/entries/${entry.id}`, { slot: "dinner" });
    expect(moved.body).toMatchObject({ slot: "dinner", position: 1 });

    const newDay = await call(ada, "PATCH", `/v1/tracker/entries/${entry.id}`, {
      date: "2026-09-02",
      name: "Renamed",
      amount: "a bowl",
      servings: 1,
      macros: { calories: 50, protein: null, carbs: null, fat: null },
    });
    expect(newDay.body).toMatchObject({
      date: "2026-09-02",
      name: "Renamed",
      amount: "a bowl",
      macros: { calories: 50, protein: null, carbs: null, fat: null },
    });
    expect((await dayOf(ada, "2026-09-02")).totals.calories).toBe(50);

    const del = await call(ada, "DELETE", `/v1/tracker/entries/${entry.id}`);
    expect(del.status).toBe(200);
    expect(del.body.id).toBe(entry.id);
    expect((await dayOf(ada, "2026-09-02")).entries).toEqual([]);
    expect((await call(ada, "DELETE", `/v1/tracker/entries/${entry.id}`)).status).toBe(404);
    const gone = await call(ada, "PATCH", `/v1/tracker/entries/${entry.id}`, { servings: 1 });
    expect(gone.status).toBe(404);
  });

  it("returns the same entry for a retried add with the same client id", async () => {
    const id = crypto.randomUUID();
    const date = "2026-09-10";
    const first = await log(ada, manual("Once", { date, id }));
    const again = await log(ada, manual("Once", { date, id }));
    expect(again).toEqual(first);
    expect((await dayOf(ada, date)).entries).toHaveLength(1);
    // Someone else's id isn't theirs to reuse.
    const clash = await call(bob, "POST", "/v1/tracker/entries", manual("Mine", { date, id }));
    expect(clash.status).toBe(400);
  });

  it("keeps settings null until saved, then upserts profile and targets", async () => {
    const empty = await call(bob, "GET", "/v1/tracker/settings");
    expect(empty.body).toEqual({ profile: null, targets: null });
    const profile = {
      sex: "female",
      birthDate: "1990-04-02",
      heightCm: 170,
      activity: "moderate",
      goal: "lose",
      weeklyRateKg: 0.5,
      proteinPerKg: 1.8,
      fatShare: 0.3,
      weightUnit: "kg",
      heightUnit: "cm",
    };
    const saved = await call(ada, "PUT", "/v1/tracker/profile", profile);
    expect(saved).toMatchObject({ status: 200, body: profile });
    const changed = await call(ada, "PUT", "/v1/tracker/profile", {
      ...profile,
      goal: "maintain",
      weightUnit: "lb",
    });
    expect(changed.body).toMatchObject({ goal: "maintain", weightUnit: "lb" });

    const targets = {
      calories: 2100,
      protein: 140,
      carbs: 230,
      fat: 70,
      overridden: { calories: true, protein: false, carbs: false, fat: false },
    };
    const t1 = await call(ada, "PUT", "/v1/tracker/targets", {
      ...targets,
      checkedInOn: "2026-04-05",
    });
    expect(t1.body).toMatchObject({ ...targets, checkedInOn: "2026-04-05" });
    // Leaving checkedInOn out keeps the current one.
    const t2 = await call(ada, "PUT", "/v1/tracker/targets", { ...targets, calories: 2200 });
    expect(t2.body).toMatchObject({ calories: 2200, checkedInOn: "2026-04-05" });
    const t3 = await call(ada, "PUT", "/v1/tracker/targets", { ...targets, checkedInOn: null });
    expect(t3.body.checkedInOn).toBeNull();

    const settings = await call(ada, "GET", "/v1/tracker/settings");
    expect(settings.body.profile).toMatchObject({ goal: "maintain" });
    expect(settings.body.targets).toMatchObject({ calories: 2100 });
    // Bob still sees nothing.
    const bobs = await call(bob, "GET", "/v1/tracker/settings");
    expect(bobs.body).toEqual({ profile: null, targets: null });
    const badProfile = await call(ada, "PUT", "/v1/tracker/profile", { ...profile, heightCm: 50 });
    expect(badProfile.status).toBe(400);
    const badTargets = await call(ada, "PUT", "/v1/tracker/targets", { ...targets, calories: 100 });
    expect(badTargets.status).toBe(400);
  });

  it("lists weigh-ins oldest first, replaces a day and deletes", async () => {
    await call(ada, "PUT", "/v1/tracker/weigh-ins/2026-10-03", { weightKg: 71 });
    await call(ada, "PUT", "/v1/tracker/weigh-ins/2026-10-01", { weightKg: 72 });
    const replaced = await call(ada, "PUT", "/v1/tracker/weigh-ins/2026-10-03", {
      weightKg: 70.126,
    });
    expect(replaced.body).toEqual({ date: "2026-10-03", weightKg: 70.13 });
    const url = "/v1/tracker/weigh-ins?from=2026-10-01&to=2026-10-31";
    expect((await call(ada, "GET", url)).body).toEqual([
      { date: "2026-10-01", weightKg: 72 },
      { date: "2026-10-03", weightKg: 70.13 },
    ]);
    const del = await call(ada, "DELETE", "/v1/tracker/weigh-ins/2026-10-01");
    expect(del.body).toEqual({ date: "2026-10-01", weightKg: 72 });
    expect((await call(ada, "DELETE", "/v1/tracker/weigh-ins/2026-10-01")).status).toBe(404);
    expect((await call(ada, "GET", url)).body).toHaveLength(1);
  });

  it("keeps Ada's diary away from Bob", async () => {
    const date = "2026-11-01";
    const entry = await log(ada, manual("Private", { date }));
    await call(ada, "PUT", `/v1/tracker/weigh-ins/${date}`, { weightKg: 65 });
    const recipe = await createRecipe(ada, { title: "Ada only" });

    const day = await dayOf(bob, date);
    expect(day.entries).toEqual([]);
    expect(day.weighIn).toBeNull();
    expect(day.totals.calories).toBe(0);
    const intake = await call(bob, "GET", `/v1/tracker/intake?from=${date}&to=${date}`);
    expect(intake.body).toEqual([]);
    const weights = await call(bob, "GET", `/v1/tracker/weigh-ins?from=${date}&to=${date}`);
    expect(weights.body).toEqual([]);
    const patch = await call(bob, "PATCH", `/v1/tracker/entries/${entry.id}`, { servings: 5 });
    expect(patch.status).toBe(404);
    expect((await call(bob, "DELETE", `/v1/tracker/entries/${entry.id}`)).status).toBe(404);
    expect((await call(bob, "DELETE", `/v1/tracker/weigh-ins/${date}`)).status).toBe(404);
    const stolen = await call(bob, "POST", "/v1/tracker/entries", {
      date,
      slot: "dinner",
      servings: 1,
      source: "recipe",
      recipeId: recipe.id,
    });
    expect(stolen.status).toBe(400);
    // Ada's entry is untouched.
    expect((await dayOf(ada, date)).entries[0]).toMatchObject({ id: entry.id, servings: 1 });
  });

  it("re-logs a recipe entry after its recipe is banished or gone", async () => {
    const recipe = await createRecipe(ada, { title: "Short-lived stew" });
    const date = "2026-12-03";
    const again = {
      date,
      slot: "dinner",
      name: "Short-lived stew",
      amount: null,
      servings: 1,
      macros: MACROS,
      source: "recipe",
    };
    // Banished: the link stays, and the recipe isn't looked up.
    expect((await call(ada, "DELETE", `/v1/recipes/${recipe.id}`)).status).toBe(200);
    const banished = await call(ada, "POST", "/v1/tracker/entries", {
      ...again,
      recipeId: recipe.id,
    });
    expect(banished.status).toBe(200);
    expect(banished.body).toMatchObject({ recipeId: recipe.id, macros: MACROS });
    // Gone (as after a hard delete): the entry's recipe id was cleared.
    const gone = await call(ada, "POST", "/v1/tracker/entries", { ...again, recipeId: null });
    expect(gone.status).toBe(200);
    expect(gone.body).toMatchObject({ source: "recipe", recipeId: null });
    // Someone else's recipe id is dropped, not linked.
    const theirs = await createRecipe(bob, { title: "Bob's stew" });
    const linked = await call(ada, "POST", "/v1/tracker/entries", {
      ...again,
      recipeId: theirs.id,
    });
    expect(linked.status).toBe(200);
    expect(linked.body.recipeId).toBeNull();
  });

  it("rejects bad input with 400", async () => {
    const base = manual("Bad", { date: "2026-12-01" });
    const post = (body: Record<string, unknown>) => call(ada, "POST", "/v1/tracker/entries", body);
    const recipe = await createRecipe(ada, { title: "For validation" });
    const { name: _rn, ...recipeNoName } = base;
    expect((await post({ ...recipeNoName, source: "recipe" })).status).toBe(400);
    expect((await post({ ...base, recipeId: recipe.id })).status).toBe(400);
    const { name: _n, ...noName } = base;
    expect((await post(noName)).status).toBe(400);
    const { macros: _m, ...noMacros } = base;
    expect((await post(noMacros)).status).toBe(400);
    expect((await post({ ...base, servings: 0 })).status).toBe(400);
    expect((await post({ ...base, servings: -1 })).status).toBe(400);
    expect((await post({ ...base, servings: TRACKER_LIMITS.servings + 1 })).status).toBe(400);
    expect((await post({ ...base, macros: { ...MACROS, protein: -5 } })).status).toBe(400);
    expect((await post({ ...base, name: "   " })).status).toBe(400);
    expect((await post({ ...base, date: "2026-02-31" })).status).toBe(400);
    expect((await post({ ...base, slot: "brunch" })).status).toBe(400);
    const badPatch = await call(ada, "PATCH", `/v1/tracker/entries/${crypto.randomUUID()}`, {
      servings: 0,
    });
    expect(badPatch.status).toBe(400);
    expect((await dayOf(ada, "2026-12-01")).entries).toEqual([]);

    expect(
      (await call(ada, "GET", "/v1/tracker/intake?from=2026-01-01&to=2027-01-02")).status,
    ).toBe(200);
    // 368 days inclusive is over the limit.
    const over = "from=2026-01-01&to=2027-01-03";
    expect((await call(ada, "GET", `/v1/tracker/intake?${over}`)).status).toBe(400);
    expect((await call(ada, "GET", `/v1/tracker/weigh-ins?${over}`)).status).toBe(400);
    const backwards = "from=2026-02-02&to=2026-02-01";
    expect((await call(ada, "GET", `/v1/tracker/intake?${backwards}`)).status).toBe(400);

    const weigh = (weightKg: number) =>
      call(ada, "PUT", "/v1/tracker/weigh-ins/2026-12-01", { weightKg });
    for (const weightKg of [19.9, 400.1, 0, -5]) expect((await weigh(weightKg)).status).toBe(400);
    expect((await weigh(20)).status).toBe(200);
    expect((await weigh(400)).status).toBe(200);
  });

  it("stops a day at its entry limit", async () => {
    const date = "2027-02-01";
    const entries = Array.from({ length: TRACKER_LIMITS.perDay }, (_, i) =>
      manual(`n${i}`, { date }),
    );
    expect((await call(ada, "POST", "/v1/tracker/entries/batch", { entries })).status).toBe(200);
    const extra = await call(ada, "POST", "/v1/tracker/entries", manual("One too many", { date }));
    expect(extra.status).toBe(400);
  });

  it("keeps a client id to its owner: a retry returns the entry, another user's id is refused", async () => {
    const id = crypto.randomUUID();
    const mine = manual("Mine", { id, date: "2027-12-06" });
    const first = await log(ada, mine);
    expect(first.id).toBe(id);
    // Bob reuses Ada's id: the same refusal as any bad request.
    const clash = await call(bob, "POST", "/v1/tracker/entries", { ...mine, name: "Bob's" });
    expect(clash.status).toBe(400);
    expect(clash.body).toMatchObject({ error: { code: "invalid_request" } });
    // Ada's entry is untouched, and her own retry is idempotent.
    expect(await log(ada, { ...mine, name: "Changed" })).toEqual(first);
    expect((await dayOf(ada, "2027-12-06")).entries).toEqual([first]);
    expect((await dayOf(bob, "2027-12-06")).entries).toEqual([]);
  });
});
