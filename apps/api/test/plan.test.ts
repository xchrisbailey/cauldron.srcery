import {
  copy,
  addDays,
  parseIngredientLine,
  PLAN_LIMITS,
  type RecipeInput,
} from "@cauldron/shared";
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

const input = (overrides: Partial<RecipeInput> = {}): RecipeInput => ({
  title: "Weeknight dal",
  description: "Red lentils simmered with spices.",
  servings: 4,
  prepMinutes: 10,
  cookMinutes: 30,
  totalMinutes: 40,
  sourcePlatform: "manual",
  sourceUrl: null,
  sourceAuthor: null,
  notes: null,
  photoKey: null,
  tags: ["Indian", "Vegetarian"],
  ingredients: lines("1 cup red lentils", "2 cloves garlic, minced", "1 tsp ground turmeric"),
  steps: [
    { section: null, text: "Rinse the lentils.", timerSeconds: null },
    { section: null, text: "Simmer 25 minutes.", timerSeconds: 1500 },
  ],
  ...overrides,
});

const create = async (cookie: string, overrides: Partial<RecipeInput> = {}) => {
  const res = await call(cookie, "POST", "/v1/recipes", input(overrides));
  expect(res.status).toBe(200);
  return res.body;
};

const addEntry = async (cookie: string, body: Record<string, unknown>) => {
  const res = await call(cookie, "POST", "/v1/plan", body);
  expect(res.status).toBe(200);
  return res.body;
};

const range = (cookie: string, from: string, to: string) =>
  call(cookie, "GET", `/v1/plan?from=${from}&to=${to}`);

const titles = (entries: ReadonlyArray<{ title: string }>) => entries.map((e) => e.title);

const slotOf = async (cookie: string, date: string, slot: string) =>
  (await range(cookie, date, date)).body.filter((e: { slot: string }) => e.slot === slot);

const free = (cookie: string, date: string, slot: string, title: string, position?: number) =>
  addEntry(cookie, { date, slot, title, ...(position === undefined ? {} : { position }) });

describe("plan", () => {
  it("requires a session", async () => {
    expect((await api.send("/v1/plan?from=2026-03-02&to=2026-03-08")).status).toBe(401);
    const res = await api.send("/v1/plan", {
      method: "POST",
      headers: { origin: WEB_ORIGIN, "content-type": "application/json" },
      body: JSON.stringify({ date: "2026-03-02", slot: "dinner", title: "x" }),
    });
    expect(res.status).toBe(401);
  });

  it("stirs a recipe into a slot and adds free text", async () => {
    const recipe = await create(ada, { title: "Stir me", servings: 6, totalMinutes: 45 });
    const entry = await addEntry(ada, { date: "2026-03-02", slot: "dinner", recipeId: recipe.id });
    expect(entry).toMatchObject({
      date: "2026-03-02",
      slot: "dinner",
      title: "Stir me",
      servings: null,
      position: 0,
      brewed: false,
      recipe: { id: recipe.id, title: "Stir me", servings: 6, totalMinutes: 45, photoKey: null },
    });
    const text = await addEntry(ada, { date: "2026-03-02", slot: "lunch", title: "Leftovers" });
    expect(text).toMatchObject({ title: "Leftovers", recipe: null, position: 0, brewed: false });
  });

  it("rejects bad entries", async () => {
    const mine = await create(ada, { title: "Mine" });
    const theirs = await create(bob, { title: "Theirs" });
    const gone = await create(ada, { title: "Gone" });
    expect((await call(ada, "DELETE", `/v1/recipes/${gone.id}`)).status).toBe(200);
    const base = { date: "2026-03-09", slot: "dinner" };
    const bad: ReadonlyArray<Record<string, unknown>> = [
      { ...base, recipeId: mine.id, title: "Both" },
      { ...base },
      { ...base, recipeId: theirs.id },
      { ...base, recipeId: gone.id },
      { ...base, title: "Bad day", date: "2026-02-31" },
      { ...base, title: "Bad slot", slot: "brunch" },
      { ...base, title: "   " },
    ];
    for (const body of bad) {
      const res = await call(ada, "POST", "/v1/plan", body);
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body.error.code).toBe("invalid_request");
    }
    expect((await range(ada, "2026-03-09", "2026-03-09")).body).toEqual([]);
  });

  it("rejects bad ranges", async () => {
    expect((await range(ada, "2026-02-31", "2026-03-05")).status).toBe(400);
    expect((await range(ada, "2026-03-10", "2026-03-05")).status).toBe(400);
    // 62 days inclusive is the most; 63 is too many.
    expect((await range(ada, "2026-01-01", addDays("2026-01-01", 61))).status).toBe(200);
    expect(
      (await range(ada, "2026-01-01", addDays("2026-01-01", PLAN_LIMITS.rangeDays))).status,
    ).toBe(400);
    const clear = await call(ada, "POST", "/v1/plan/clear", {
      from: "2026-01-01",
      to: addDays("2026-01-01", PLAN_LIMITS.rangeDays),
    });
    expect(clear.status).toBe(400);
    expect(
      (await call(ada, "POST", "/v1/plan/clear", { from: "2026-03-10", to: "2026-03-05" })).status,
    ).toBe(400);
  });

  it("lists by range in day, slot and position order, scoped to the owner", async () => {
    const day = "2026-04-06";
    await free(ada, addDays(day, 1), "snack", "d2 snack");
    await free(ada, day, "dinner", "d1 dinner");
    await free(ada, day, "breakfast", "d1 breakfast");
    await free(ada, day, "snack", "d1 snack");
    await free(ada, day, "lunch", "d1 lunch");
    await free(ada, day, "lunch", "d1 lunch 2");
    await free(ada, addDays(day, 7), "dinner", "outside");
    await free(ada, addDays(day, -1), "dinner", "before");
    await free(bob, day, "dinner", "bob's");

    const res = await range(ada, day, addDays(day, 6));
    expect(res.status).toBe(200);
    expect(titles(res.body)).toEqual([
      "d1 breakfast",
      "d1 lunch",
      "d1 lunch 2",
      "d1 dinner",
      "d1 snack",
      "d2 snack",
    ]);
    expect(titles((await range(bob, day, addDays(day, 6))).body)).toEqual(["bob's"]);
  });

  it("hides entries from other users", async () => {
    const entry = await free(ada, "2026-04-20", "dinner", "Private");
    const patch = await call(bob, "PATCH", `/v1/plan/${entry.id}`, { servings: 2 });
    expect(patch.status).toBe(404);
    expect(patch.body.error.code).toBe("not_found");
    expect((await call(bob, "DELETE", `/v1/plan/${entry.id}`)).status).toBe(404);
    expect((await range(ada, "2026-04-20", "2026-04-20")).body).toHaveLength(1);
    const missing = "00000000-0000-4000-8000-000000000000";
    expect((await call(ada, "DELETE", `/v1/plan/${missing}`)).status).toBe(404);
    expect((await call(ada, "PATCH", `/v1/plan/not-a-uuid`, {})).status).toBe(400);
  });

  it("inserts at a position and shifts siblings", async () => {
    const day = "2026-05-04";
    await free(ada, day, "dinner", "a");
    await free(ada, day, "dinner", "b");
    const c = await free(ada, day, "dinner", "c", 1);
    expect(c.position).toBe(1);
    await free(ada, day, "dinner", "front", 0);
    // Past the end clamps to the end.
    const last = await free(ada, day, "dinner", "last", 99);
    const slot = await slotOf(ada, day, "dinner");
    expect(titles(slot)).toEqual(["front", "a", "c", "b", "last"]);
    expect(slot.map((e: { position: number }) => e.position)).toEqual([0, 1, 2, 3, 4]);
    expect(last.position).toBe(4);
  });

  it("moves entries between slots and days, keeping both dense", async () => {
    const day = "2026-05-11";
    const a = await free(ada, day, "dinner", "a");
    await free(ada, day, "dinner", "b");
    await free(ada, day, "dinner", "c");
    await free(ada, day, "lunch", "x");
    await free(ada, day, "lunch", "y");

    const moved = await call(ada, "PATCH", `/v1/plan/${a.id}`, { slot: "lunch", position: 1 });
    expect(moved.status).toBe(200);
    expect(moved.body).toMatchObject({ slot: "lunch", position: 1 });
    let dinner = await slotOf(ada, day, "dinner");
    let lunch = await slotOf(ada, day, "lunch");
    expect(titles(dinner)).toEqual(["b", "c"]);
    expect(dinner.map((e: { position: number }) => e.position)).toEqual([0, 1]);
    expect(titles(lunch)).toEqual(["x", "a", "y"]);
    expect(lunch.map((e: { position: number }) => e.position)).toEqual([0, 1, 2]);

    // To another day, no position: the end.
    const next = addDays(day, 1);
    await free(ada, next, "lunch", "z");
    const far = await call(ada, "PATCH", `/v1/plan/${a.id}`, { date: next });
    expect(far.body).toMatchObject({ date: next, slot: "lunch", position: 1 });
    lunch = await slotOf(ada, day, "lunch");
    expect(titles(lunch)).toEqual(["x", "y"]);
    expect(lunch.map((e: { position: number }) => e.position)).toEqual([0, 1]);
    expect(titles(await slotOf(ada, next, "lunch"))).toEqual(["z", "a"]);
    dinner = await slotOf(ada, day, "dinner");
    expect(titles(dinner)).toEqual(["b", "c"]);
  });

  it("reorders within a slot", async () => {
    const day = "2026-05-18";
    const a = await free(ada, day, "dinner", "a");
    await free(ada, day, "dinner", "b");
    const c = await free(ada, day, "dinner", "c");
    const down = await call(ada, "PATCH", `/v1/plan/${a.id}`, { position: 2 });
    expect(down.body.position).toBe(2);
    expect(titles(await slotOf(ada, day, "dinner"))).toEqual(["b", "c", "a"]);
    await call(ada, "PATCH", `/v1/plan/${c.id}`, { position: 0 });
    const slot = await slotOf(ada, day, "dinner");
    expect(titles(slot)).toEqual(["c", "b", "a"]);
    expect(slot.map((e: { position: number }) => e.position)).toEqual([0, 1, 2]);
  });

  it("changes servings, renames free text, and refuses to rename a recipe entry", async () => {
    const day = "2026-05-25";
    const recipe = await create(ada, { title: "Real food" });
    const dish = await addEntry(ada, { date: day, slot: "dinner", recipeId: recipe.id });
    const set = await call(ada, "PATCH", `/v1/plan/${dish.id}`, { servings: 8 });
    expect(set.status).toBe(200);
    expect(set.body.servings).toBe(8);
    const reset = await call(ada, "PATCH", `/v1/plan/${dish.id}`, { servings: null });
    expect(reset.body.servings).toBeNull();
    for (const servings of [0, 1.5, 10_000]) {
      expect((await call(ada, "PATCH", `/v1/plan/${dish.id}`, { servings })).status).toBe(400);
    }

    const text = await free(ada, day, "lunch", "Leftovers");
    const renamed = await call(ada, "PATCH", `/v1/plan/${text.id}`, { title: "Takeout" });
    expect(renamed.status).toBe(200);
    expect(renamed.body.title).toBe("Takeout");

    const refused = await call(ada, "PATCH", `/v1/plan/${dish.id}`, { title: "Nope" });
    expect(refused.status).toBe(400);
    expect(refused.body.error.code).toBe("invalid_request");
    expect((await call(ada, "PATCH", `/v1/plan/${text.id}`, { title: "  " })).status).toBe(400);
  });

  it("removes an entry and keeps positions dense", async () => {
    const day = "2026-06-01";
    await free(ada, day, "dinner", "a");
    const b = await free(ada, day, "dinner", "b");
    await free(ada, day, "dinner", "c");
    const res = await call(ada, "DELETE", `/v1/plan/${b.id}`);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ id: b.id, title: "b" });
    const slot = await slotOf(ada, day, "dinner");
    expect(titles(slot)).toEqual(["a", "c"]);
    expect(slot.map((e: { position: number }) => e.position)).toEqual([0, 1]);
    expect((await call(ada, "DELETE", `/v1/plan/${b.id}`)).status).toBe(404);
  });

  it("keeps the title when the recipe is banished and reconnects on restore", async () => {
    const day = "2026-06-08";
    const recipe = await create(ada, { title: "Fleeting" });
    const entry = await addEntry(ada, { date: day, slot: "dinner", recipeId: recipe.id });
    await call(ada, "DELETE", `/v1/recipes/${recipe.id}`);
    const gone = (await range(ada, day, day)).body[0];
    expect(gone).toMatchObject({ id: entry.id, title: "Fleeting", recipe: null, brewed: false });

    // A banished recipe's entry can still be moved.
    expect(
      (await call(ada, "PATCH", `/v1/plan/${entry.id}`, { slot: "lunch" })).body.recipe,
    ).toBeNull();

    await call(ada, "POST", `/v1/recipes/${recipe.id}/restore`);
    const back = (await range(ada, day, day)).body[0];
    expect(back.recipe).toMatchObject({ id: recipe.id, title: "Fleeting" });
  });

  it("marks entries brewed on the day the recipe was cooked", async () => {
    const day = "2026-06-15";
    const recipe = await create(ada, { title: "Cooked once" });
    await addEntry(ada, { date: day, slot: "dinner", recipeId: recipe.id });
    await addEntry(ada, { date: addDays(day, 1), slot: "dinner", recipeId: recipe.id });
    await free(ada, day, "lunch", "No recipe");
    await call(ada, "POST", `/v1/recipes/${recipe.id}/cooked`, { on: day });
    const res = (await range(ada, day, addDays(day, 1))).body;
    expect(res.map((e: { title: string; brewed: boolean }) => [e.title, e.brewed])).toEqual([
      ["No recipe", false],
      ["Cooked once", true],
      ["Cooked once", false],
    ]);
    // Another user cooking their own recipe on the day doesn't count.
    const theirs = await create(bob, { title: "Cooked once" });
    await call(bob, "POST", `/v1/recipes/${theirs.id}/cooked`, { on: addDays(day, 1) });
    const again = (await range(ada, day, addDays(day, 1))).body;
    expect(again[2].brewed).toBe(false);
  });

  it("copies a week to another, shifted, appending to what's there", async () => {
    const a = "2026-07-06";
    const b = "2026-07-13";
    const recipe = await create(ada, { title: "Weekly" });
    await addEntry(ada, { date: a, slot: "dinner", recipeId: recipe.id, servings: 3 });
    await free(ada, a, "dinner", "second");
    await free(ada, addDays(a, 2), "lunch", "Wed lunch");
    await free(ada, addDays(a, 6), "snack", "Sun snack");
    await free(ada, addDays(a, 21), "dinner", "past the target week");
    await free(ada, b, "dinner", "already");

    const res = await call(ada, "POST", "/v1/plan/copy", { from: a, to: b });
    expect(res.status).toBe(200);
    const week = res.body as Array<{
      date: string;
      slot: string;
      title: string;
      position: number;
      servings: number | null;
      recipe: unknown;
    }>;
    expect(week.every((e) => e.date >= b && e.date <= addDays(b, 6))).toBe(true);
    expect(week.map((e) => [e.date, e.slot, e.title, e.position])).toEqual([
      [b, "dinner", "already", 0],
      [b, "dinner", "Weekly", 1],
      [b, "dinner", "second", 2],
      [addDays(b, 2), "lunch", "Wed lunch", 0],
      [addDays(b, 6), "snack", "Sun snack", 0],
    ]);
    expect(week[1]).toMatchObject({ servings: 3, recipe: { title: "Weekly" } });
    // The source week is untouched.
    expect(await slotOf(ada, a, "dinner")).toHaveLength(2);
    // The target week's own listing agrees; nothing lands past it.
    expect((await range(ada, b, addDays(b, 6))).body).toHaveLength(5);
    expect(titles((await range(ada, addDays(b, 7), addDays(b, 10))).body)).toEqual([]);
  });

  it("refuses to copy a week onto itself and copies nothing from another user's week", async () => {
    const same = await call(ada, "POST", "/v1/plan/copy", { from: "2026-07-06", to: "2026-07-06" });
    expect(same.status).toBe(400);
    expect(same.body.error.code).toBe("invalid_request");
    await free(bob, "2026-08-03", "dinner", "bob only");
    const res = await call(ada, "POST", "/v1/plan/copy", { from: "2026-08-03", to: "2026-08-10" });
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
    expect(
      (await call(ada, "POST", "/v1/plan/copy", { from: "2026-02-31", to: "2026-08-10" })).status,
    ).toBe(400);
  });

  it("clears a range and returns what it removed", async () => {
    const day = "2026-09-07";
    await free(ada, addDays(day, -1), "dinner", "before");
    await free(ada, day, "dinner", "in 1");
    await free(ada, addDays(day, 3), "lunch", "in 2");
    await free(ada, addDays(day, 6), "dinner", "in 3");
    await free(ada, addDays(day, 7), "dinner", "after");
    await free(bob, day, "dinner", "bob's");
    const res = await call(ada, "POST", "/v1/plan/clear", { from: day, to: addDays(day, 6) });
    expect(res.status).toBe(200);
    expect(titles(res.body)).toEqual(["in 1", "in 2", "in 3"]);
    const left = await range(ada, addDays(day, -1), addDays(day, 7));
    expect(titles(left.body)).toEqual(["before", "after"]);
    expect(titles((await range(bob, day, day)).body)).toEqual(["bob's"]);
    const empty = await call(ada, "POST", "/v1/plan/clear", { from: day, to: addDays(day, 6) });
    expect(empty.body).toEqual([]);
  });

  it("limits entries per slot", async () => {
    const day = "2026-10-05";
    for (let i = 0; i < PLAN_LIMITS.perSlot; i++) await free(ada, day, "snack", `s${i}`);
    const over = await call(ada, "POST", "/v1/plan", {
      date: day,
      slot: "snack",
      title: "one more",
    });
    expect(over.status).toBe(400);
    expect(over.body.error.message).toBe(copy.week.slotFull.text);
    expect(await slotOf(ada, day, "snack")).toHaveLength(PLAN_LIMITS.perSlot);
    // Moving into a full slot is refused too; another slot is fine.
    const dinner = await free(ada, day, "dinner", "mover");
    const move = await call(ada, "PATCH", `/v1/plan/${dinner.id}`, { slot: "snack" });
    expect(move.status).toBe(400);
    expect(await slotOf(ada, day, "dinner")).toHaveLength(1);
    // Within the full slot, reordering still works.
    const first = (await slotOf(ada, day, "snack"))[0];
    expect((await call(ada, "PATCH", `/v1/plan/${first.id}`, { position: 5 })).status).toBe(200);
  });

  it("adds an entry once when the client retries with the same id", async () => {
    const id = crypto.randomUUID();
    const day = "2026-11-02";
    const first = await addEntry(ada, { id, date: day, slot: "lunch", title: "Soup" });
    expect(first.id).toBe(id);
    const again = await addEntry(ada, { id, date: day, slot: "lunch", title: "Soup" });
    expect(again).toEqual(first);
    expect(await slotOf(ada, day, "lunch")).toHaveLength(1);
    // Another user can't claim or read it by reusing the id.
    const theirs = await call(bob, "POST", "/v1/plan", {
      id,
      date: day,
      slot: "lunch",
      title: "x",
    });
    expect(theirs.status).toBe(400);
  });

  it("renames the entry of a banished recipe like free text", async () => {
    const recipe = await create(ada, { title: "Short-lived stew" });
    const planned = await addEntry(ada, {
      date: "2026-11-03",
      slot: "dinner",
      recipeId: recipe.id,
    });
    expect((await call(ada, "DELETE", `/v1/recipes/${recipe.id}`)).status).toBe(200);
    const renamed = await call(ada, "PATCH", `/v1/plan/${planned.id}`, { title: "Takeaway" });
    expect(renamed.status).toBe(200);
    expect(renamed.body.title).toBe("Takeaway");
  });
});
