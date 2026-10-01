import { parseIngredientLine, type RecipeInput } from "@cauldron/shared";
import { seedRecipes } from "../../../packages/db/src/seed-recipes.ts";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

const PASSWORD = "correct-horse-1";

let api: AuthApi;
let ada: string;
let bob: string;
let nextUser = 0;

const signUpVerified = async (email: string) => {
  const before = (await api.outbox()).length;
  await api.post("/v1/auth/sign-up/email", { email, password: PASSWORD, name: "Cook" });
  const sent = (await api.waitForOutbox(before + 1)).slice(before).filter((m) => m.to === email);
  const cookie = cookieOf(await api.send(api.linkIn(sent[0]!)));
  if (!cookie) throw new Error("verification didn't sign in");
  return cookie;
};

/** A fresh cook, so pantry marks (remembered across weeks) don't leak between tests. */
const freshCook = () => signUpVerified(`cook${nextUser++}@example.com`);

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

/** Ingredient lines like the editor sends them; "## " lines start a section. */
const lines = (...raw: ReadonlyArray<string>) => {
  let section: string | null = null;
  const out: Array<ReturnType<typeof parseIngredientLine> & { section: string | null }> = [];
  for (const text of raw) {
    if (text.startsWith("## ")) {
      section = text.slice(3);
      continue;
    }
    out.push({ ...parseIngredientLine(text), section });
  }
  return out;
};

const input = (title: string, ingredients: ReadonlyArray<string>, servings = 4): RecipeInput => ({
  title,
  description: null,
  servings,
  prepMinutes: 10,
  cookMinutes: 30,
  totalMinutes: 40,
  sourcePlatform: "manual",
  sourceUrl: null,
  sourceAuthor: null,
  notes: null,
  photoKey: null,
  tags: [],
  ingredients: lines(...ingredients),
  steps: [{ section: null, text: "Cook it.", timerSeconds: null }],
});

const create = async (
  cookie: string,
  title: string,
  ingredients: ReadonlyArray<string>,
  servings = 4,
) => {
  const res = await call(cookie, "POST", "/v1/recipes", input(title, ingredients, servings));
  expect(res.status).toBe(200);
  return res.body;
};

const plan = async (cookie: string, recipeId: string, date: string, extra: object = {}) => {
  const res = await call(cookie, "POST", "/v1/plan", { recipeId, date, slot: "dinner", ...extra });
  expect(res.status).toBe(200);
  return res.body;
};

const gatherWeek = async (cookie: string, weekStart: string) => {
  const res = await call(cookie, "GET", `/v1/gather/${weekStart}`);
  expect(res.status).toBe(200);
  return res.body;
};

const byKey = (list: { items: ReadonlyArray<any> }, itemKey: string) =>
  list.items.filter((i) => i.itemKey === itemKey);

const WEEK = "2026-10-05";

describe("gather", () => {
  it("requires a session", async () => {
    const id = "00000000-0000-4000-8000-000000000000";
    expect((await api.send(`/v1/gather/${WEEK}`)).status).toBe(401);
    for (const [method, path, body] of [
      ["POST", `/v1/gather/${WEEK}/items`, { line: "2 lemons" }],
      ["PATCH", `/v1/gather/items/${id}`, { checked: true }],
      ["DELETE", `/v1/gather/items/${id}`, undefined],
    ] as const) {
      const res = await api.send(path, {
        method,
        headers: {
          origin: WEB_ORIGIN,
          ...(body ? { "content-type": "application/json" } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      expect(res.status, `${method} ${path}`).toBe(401);
    }
  });

  describe("a week of the five seeded recipes (#19 done-when)", () => {
    const SHAKSHUKA = "Shakshuka with feta";
    const CHICKEN = "Weeknight chicken thighs with lemon and garlic";
    const OATS = "Overnight oats";
    const SOUP = "Tomato and white bean soup";
    const COOKIES = "Brown butter chocolate chip cookies";

    type Expected = readonly [
      item: string,
      min: number | null,
      max: number | null,
      unit: string | null,
      aisle: string,
      titles: ReadonlyArray<string>,
    ];

    // Worked out by hand from the lines in packages/db/src/seed-recipes.ts.
    // Shakshuka is planned at 8 servings (twice its 4), the oats twice at their
    // own 2, everything else once at its own servings.
    // Store order: aisle, then item name.
    const EXPECTED: ReadonlyArray<Expected> = [
      // produce
      ["berries", 2, null, "cup", "produce", [OATS]],
      ["carrots", 2, null, null, "produce", [SOUP]],
      ["chopped parsley", 4, null, "tbsp", "produce", [SHAKSHUKA]],
      ["garlic", 16, null, "clove", "produce", [CHICKEN, SHAKSHUKA, SOUP]],
      ["lemon", 1, null, null, "produce", [CHICKEN]],
      ["onion", 3, null, null, "produce", [SHAKSHUKA, SOUP]],
      ["red bell pepper", 2, null, null, "produce", [SHAKSHUKA]],
      ["small potatoes", 1.5, null, "lb", "produce", [CHICKEN]],
      ["spinach", 2, null, "cup", "produce", [SOUP]],
      ["thyme", 4, null, "sprig", "produce", [CHICKEN]],
      // meat
      ["chicken thighs", 2, null, "lb", "meat", [CHICKEN]],
      // dairy
      ["crumbled feta", 1, null, "cup", "dairy", [SHAKSHUKA]],
      ["large eggs", 14, null, null, "dairy", [COOKIES, SHAKSHUKA]],
      ["milk", 2, null, "cup", "dairy", [OATS]],
      ["plain yogurt", 1, null, "cup", "dairy", [OATS]],
      ["unsalted butter", 1, null, "cup", "dairy", [COOKIES]],
      // pantry
      ["all-purpose flour", 2.25, null, "cup", "pantry", [COOKIES]],
      ["baking soda", 1, null, "tsp", "pantry", [COOKIES]],
      ["cannellini beans", 2, null, "can", "pantry", [SOUP]],
      ["chia seeds", 2, null, "tbsp", "pantry", [OATS]],
      ["chocolate chips", 1.5, null, "cup", "pantry", [COOKIES]],
      ["crushed tomatoes", 2, null, "can", "pantry", [SHAKSHUKA]],
      ["diced tomatoes", 1, null, "can", "pantry", [SOUP]],
      ["granulated sugar", 0.5, null, "cup", "pantry", [COOKIES]],
      ["maple syrup", 2, 4, "tbsp", "pantry", [OATS]],
      ["olive oil", 10, null, "tbsp", "pantry", [CHICKEN, SHAKSHUKA, SOUP]],
      ["packed brown sugar", 1, null, "cup", "pantry", [COOKIES]],
      ["rolled oats", 2, null, "cup", "pantry", [OATS]],
      ["toasted almonds", 4, null, "tbsp", "pantry", [OATS]],
      ["vanilla extract", 2, null, "tsp", "pantry", [COOKIES]],
      ["vegetable stock", 4, null, "cup", "pantry", [SOUP]],
      // spices
      ["black pepper", 0.5, null, "tsp", "spices", [CHICKEN]],
      ["chili flakes", 0.5, null, "tsp", "spices", [SHAKSHUKA]],
      ["dried oregano", 1, null, "tsp", "spices", [SOUP]],
      ["Flaky salt", null, null, null, "spices", [COOKIES]],
      ["ground cumin", 2, null, "tsp", "spices", [SHAKSHUKA]],
      ["kosher salt", 2, null, "tsp", "spices", [CHICKEN, COOKIES]],
      ["Pinch of salt", null, null, null, "spices", [OATS]],
      ["Salt", null, null, null, "spices", [SOUP]],
      ["Salt and pepper", null, null, null, "spices", [SHAKSHUKA]],
      ["smoked paprika", 2, null, "tsp", "spices", [SHAKSHUKA]],
    ];

    const seedIds = async (cookie: string) => {
      const ids = new Map<string, string>();
      for (const r of seedRecipes) {
        const created = await call(cookie, "POST", "/v1/recipes", {
          title: r.title,
          description: r.description,
          servings: r.servings,
          prepMinutes: r.prepMinutes,
          cookMinutes: r.cookMinutes,
          totalMinutes: r.prepMinutes + r.cookMinutes,
          sourcePlatform: "manual",
          sourceUrl: null,
          sourceAuthor: null,
          notes: r.notes ?? null,
          photoKey: null,
          tags: r.tags.map((t) => t.name),
          ingredients: lines(...r.ingredients),
          steps: r.steps.map((s) => ({
            section: null,
            text: s.text,
            timerSeconds: s.timerSeconds ?? null,
          })),
        });
        expect(created.status).toBe(200);
        ids.set(r.title, created.body.id);
      }
      return ids;
    };

    it("merges, groups and attributes the week the way a hand-checked list does", async () => {
      const cook = await freshCook();
      const ids = await seedIds(cook);
      const id = (title: string) => ids.get(title)!;
      await plan(cook, id(SHAKSHUKA), "2026-10-05", { servings: 8 });
      await plan(cook, id(CHICKEN), "2026-10-06");
      await plan(cook, id(OATS), "2026-10-07", { slot: "breakfast" });
      await plan(cook, id(OATS), "2026-10-08", { slot: "breakfast", servings: 2 });
      await plan(cook, id(SOUP), "2026-10-09", { slot: "lunch" });
      await plan(cook, id(COOKIES), "2026-10-10", { slot: "snack" });

      const list = await gatherWeek(cook, WEEK);
      expect(list.weekStart).toBe(WEEK);
      // The oats are planned twice but count once.
      expect(list.recipeCount).toBe(5);

      const actual: Array<Expected> = list.items.map((i: any) => [
        i.item,
        i.quantity?.min ?? null,
        i.quantity?.max ?? null,
        i.unit,
        i.aisle,
        i.sources
          .map((s: any) => s.title)
          .sort((a: unknown, b: unknown) => String(a).localeCompare(String(b))),
      ]);
      const expected = EXPECTED.map(
        ([item, min, max, unit, aisle, titles]) =>
          [
            item,
            min,
            max,
            unit,
            aisle,
            [...titles].sort((a: unknown, b: unknown) => String(a).localeCompare(String(b))),
          ] as const,
      );
      expect(actual).toEqual(expected);
      expect(list.items.every((i: any) => !i.checked && !i.manual && !i.inPantry)).toBe(true);
    });

    it("scales each recipe's own contribution, and sums a recipe planned twice", async () => {
      const cook = await freshCook();
      const ids = await seedIds(cook);
      await plan(cook, ids.get(SHAKSHUKA)!, "2026-10-05", { servings: 8 });
      await plan(cook, ids.get(OATS)!, "2026-10-07", { slot: "breakfast" });
      await plan(cook, ids.get(OATS)!, "2026-10-08", { slot: "breakfast" });
      await plan(cook, ids.get(COOKIES)!, "2026-10-10", { slot: "snack" });
      const list = await gatherWeek(cook, WEEK);
      const eggs = byKey(list, "egg")[0];
      expect(eggs.sources.map((s: any) => [s.title, s.quantity, s.unit])).toEqual([
        [COOKIES, { min: 2, max: null }, null],
        [SHAKSHUKA, { min: 12, max: null }, null],
      ]);
      const milk = byKey(list, "milk")[0];
      expect(milk.sources).toHaveLength(1);
      expect(milk.sources[0].quantity).toEqual({ min: 2, max: null });
      expect(milk.quantity).toEqual({ min: 2, max: null });
    });
  });

  describe("manual items", () => {
    it("parses a line into quantity, item and aisle", async () => {
      const cook = await freshCook();
      const added = await call(cook, "POST", `/v1/gather/2026-11-02/items`, { line: "2 lemons" });
      expect(added.status).toBe(200);
      expect(added.body).toMatchObject({
        item: "lemons",
        itemKey: "lemon",
        quantity: { min: 2, max: null },
        unit: null,
        aisle: "produce",
        manual: true,
        checked: false,
        inPantry: false,
        sources: [],
      });
      const list = await gatherWeek(cook, "2026-11-02");
      expect(list.items.map((i: any) => i.id)).toEqual([added.body.id]);
    });

    it("keeps a bare name with no amount", async () => {
      const cook = await freshCook();
      const added = await call(cook, "POST", `/v1/gather/2026-11-02/items`, { line: "oat milk" });
      expect(added.status).toBe(200);
      expect(added.body).toMatchObject({
        item: "oat milk",
        quantity: null,
        unit: null,
        manual: true,
      });
    });

    it("rejects an empty line, an over-long line and a bad week", async () => {
      const cook = await freshCook();
      expect(
        (await call(cook, "POST", `/v1/gather/2026-11-02/items`, { line: "   " })).status,
      ).toBe(400);
      expect((await call(cook, "POST", `/v1/gather/2026-11-02/items`, {})).status).toBe(400);
      expect(
        (await call(cook, "POST", `/v1/gather/2026-11-02/items`, { line: "x".repeat(2000) }))
          .status,
      ).toBe(400);
      expect(
        (await call(cook, "POST", `/v1/gather/2026-02-31/items`, { line: "2 lemons" })).status,
      ).toBe(400);
      expect((await call(cook, "GET", `/v1/gather/not-a-date`)).status).toBe(400);
    });

    it("can be removed, but gathered items can't", async () => {
      const cook = await freshCook();
      const recipe = await create(cook, "Remove test", ["1 cup flour"]);
      await plan(cook, recipe.id, "2026-11-03");
      const manual = (await call(cook, "POST", `/v1/gather/2026-11-02/items`, { line: "2 lemons" }))
        .body;
      const list = await gatherWeek(cook, "2026-11-02");
      const gathered = byKey(list, "flour")[0];
      expect(gathered.manual).toBe(false);

      const refused = await call(cook, "DELETE", `/v1/gather/items/${gathered.id}`);
      expect(refused.status).toBe(400);
      expect(refused.body.error.code).toBeTruthy();
      expect(byKey(await gatherWeek(cook, "2026-11-02"), "flour")).toHaveLength(1);

      const removed = await call(cook, "DELETE", `/v1/gather/items/${manual.id}`);
      expect(removed.status).toBe(200);
      expect(removed.body.id).toBe(manual.id);
      const after = await gatherWeek(cook, "2026-11-02");
      expect(after.items.map((i: any) => i.id)).toEqual([gathered.id]);
      expect((await call(cook, "DELETE", `/v1/gather/items/${manual.id}`)).status).toBe(404);
    });

    it("an empty week has no recipes and only manual items", async () => {
      const cook = await freshCook();
      const empty = await gatherWeek(cook, "2026-12-07");
      expect(empty).toEqual({ weekStart: "2026-12-07", recipeCount: 0, items: [] });
      await call(cook, "POST", `/v1/gather/2026-12-07/items`, { line: "2 lemons" });
      await call(cook, "POST", `/v1/gather/2026-12-07/items`, { line: "oat milk" });
      const list = await gatherWeek(cook, "2026-12-07");
      expect(list.recipeCount).toBe(0);
      expect(list.items).toHaveLength(2);
      expect(list.items.every((i: any) => i.manual)).toBe(true);
      // The week is the seven days from weekStart, so the day before is empty.
      expect((await gatherWeek(cook, "2026-12-06")).items).toEqual([]);
    });
  });

  describe("regenerating", () => {
    it("follows the plan and keeps manual items and checks", async () => {
      const cook = await freshCook();
      const week = "2026-11-09";
      const pasta = await create(cook, "Pasta night", ["200 g spaghetti", "2 eggs", "1 tsp salt"]);
      const salad = await create(cook, "Green salad", ["2 lettuce", "2 eggs"]);
      const pastaEntry = await plan(cook, pasta.id, "2026-11-09");
      const saladEntry = await plan(cook, salad.id, "2026-11-10");

      const first = await gatherWeek(cook, week);
      expect(first.recipeCount).toBe(2);
      expect(
        first.items
          .map((i: any) => i.itemKey)
          .sort((a: unknown, b: unknown) => String(a).localeCompare(String(b))),
      ).toEqual(
        ["egg", "lettuce", "salt", "spaghetti"].sort((a: unknown, b: unknown) =>
          String(a).localeCompare(String(b)),
        ),
      );
      expect(byKey(first, "egg")[0].quantity).toEqual({ min: 4, max: null });

      const manual = (await call(cook, "POST", `/v1/gather/${week}/items`, { line: "2 lemons" }))
        .body;
      await call(cook, "PATCH", `/v1/gather/items/${manual.id}`, { checked: true });
      const spaghetti = byKey(first, "spaghetti")[0];
      await call(cook, "PATCH", `/v1/gather/items/${spaghetti.id}`, { checked: true });

      // Regenerating with an unchanged plan changes nothing and keeps ids.
      const again = await gatherWeek(cook, week);
      expect(
        again.items
          .map((i: any) => i.id)
          .sort((a: unknown, b: unknown) => String(a).localeCompare(String(b))),
      ).toEqual(
        [...first.items.map((i: any) => i.id), manual.id].sort((a, b) =>
          String(a).localeCompare(String(b)),
        ),
      );

      // Add a recipe, remove one, change servings.
      const curry = await create(cook, "Curry", ["1 tbsp curry powder", "1 cup rice"]);
      await plan(cook, curry.id, "2026-11-11");
      expect((await call(cook, "DELETE", `/v1/plan/${saladEntry.id}`)).status).toBe(200);
      expect((await call(cook, "PATCH", `/v1/plan/${pastaEntry.id}`, { servings: 2 })).status).toBe(
        200,
      );

      const next = await gatherWeek(cook, week);
      expect(next.recipeCount).toBe(2);
      const keys = next.items
        .map((i: any) => i.itemKey)
        .sort((a: unknown, b: unknown) => String(a).localeCompare(String(b)));
      expect(keys).toEqual(
        ["curry powder", "egg", "lemon", "rice", "salt", "spaghetti"].sort((a, b) =>
          String(a).localeCompare(String(b)),
        ),
      );
      expect(keys).not.toContain("lettuce");
      // Fewer servings: the amounts shrink, the check on spaghetti stays, ids stay.
      const spaghettiNow = byKey(next, "spaghetti")[0];
      expect(spaghettiNow.id).toBe(spaghetti.id);
      expect(spaghettiNow.quantity).toEqual({ min: 100, max: null });
      expect(spaghettiNow.checked).toBe(true);
      expect(byKey(next, "egg")[0].quantity).toEqual({ min: 1, max: null });
      expect(byKey(next, "egg")[0].sources.map((s: any) => s.title)).toEqual(["Pasta night"]);
      // Manual item and its check survive; new rows are unchecked.
      const lemon = byKey(next, "lemon")[0];
      expect(lemon).toMatchObject({ id: manual.id, manual: true, checked: true });
      expect(byKey(next, "rice")[0]).toMatchObject({ checked: false, manual: false });
    });

    it("unchecks a gathered row when its quantity grows, keeps the check when it shrinks", async () => {
      const cook = await freshCook();
      const week = "2026-11-16";
      const recipe = await create(cook, "Pancakes", ["1 cup flour"], 4);
      const entry = await plan(cook, recipe.id, "2026-11-17");
      const flour = byKey(await gatherWeek(cook, week), "flour")[0];
      await call(cook, "PATCH", `/v1/gather/items/${flour.id}`, { checked: true });

      // Same quantity: stays checked.
      expect(byKey(await gatherWeek(cook, week), "flour")[0].checked).toBe(true);

      // Doubled servings: needs more, so unchecked.
      await call(cook, "PATCH", `/v1/plan/${entry.id}`, { servings: 8 });
      const grown = byKey(await gatherWeek(cook, week), "flour")[0];
      expect(grown.id).toBe(flour.id);
      expect(grown.quantity).toEqual({ min: 2, max: null });
      expect(grown.checked).toBe(false);

      // Checked again, then fewer servings: smaller, so still checked.
      await call(cook, "PATCH", `/v1/gather/items/${flour.id}`, { checked: true });
      await call(cook, "PATCH", `/v1/plan/${entry.id}`, { servings: 6 });
      const shrunk = byKey(await gatherWeek(cook, week), "flour")[0];
      expect(shrunk.quantity).toEqual({ min: 1.5, max: null });
      expect(shrunk.checked).toBe(true);
    });

    it("unchecks when another recipe adds to a checked row", async () => {
      const cook = await freshCook();
      const week = "2026-11-23";
      const a = await create(cook, "Eggs A", ["2 eggs"]);
      const b = await create(cook, "Eggs B", ["3 eggs"]);
      await plan(cook, a.id, "2026-11-23");
      const eggs = byKey(await gatherWeek(cook, week), "egg")[0];
      await call(cook, "PATCH", `/v1/gather/items/${eggs.id}`, { checked: true });
      await plan(cook, b.id, "2026-11-24");
      const next = byKey(await gatherWeek(cook, week), "egg")[0];
      expect(next.quantity).toEqual({ min: 5, max: null });
      expect(next.checked).toBe(false);
      expect(next.sources.map((s: any) => s.title)).toEqual(["Eggs A", "Eggs B"]);
    });

    it("drops the rows of a banished recipe on the next read", async () => {
      const cook = await freshCook();
      const week = "2026-11-30";
      const keep = await create(cook, "Keeper", ["1 cup rice"]);
      const banish = await create(cook, "Banished", ["1 cup rice", "2 carrots"]);
      await plan(cook, keep.id, "2026-11-30");
      await plan(cook, banish.id, "2026-12-01");
      const before = await gatherWeek(cook, week);
      expect(before.recipeCount).toBe(2);
      expect(byKey(before, "rice")[0].quantity).toEqual({ min: 2, max: null });
      expect(byKey(before, "carrot")).toHaveLength(1);

      expect((await call(cook, "DELETE", `/v1/recipes/${banish.id}`)).status).toBe(200);
      const after = await gatherWeek(cook, week);
      expect(after.recipeCount).toBe(1);
      expect(byKey(after, "carrot")).toHaveLength(0);
      expect(byKey(after, "rice")[0].quantity).toEqual({ min: 1, max: null });
      expect(byKey(after, "rice")[0].sources.map((s: any) => s.title)).toEqual(["Keeper"]);

      // Restoring brings them back.
      await call(cook, "POST", `/v1/recipes/${banish.id}/restore`);
      expect(byKey(await gatherWeek(cook, week), "carrot")).toHaveLength(1);
    });

    it("ignores free-text entries and entries outside the week", async () => {
      const cook = await freshCook();
      const recipe = await create(cook, "Edge days", ["1 cup rice"]);
      await plan(cook, recipe.id, "2026-12-13");
      await plan(cook, recipe.id, "2026-12-22");
      await call(cook, "POST", "/v1/plan", {
        date: "2026-12-15",
        slot: "lunch",
        title: "Leftovers",
      });
      const week = await gatherWeek(cook, "2026-12-14");
      expect(week.recipeCount).toBe(0);
      expect(week.items).toEqual([]);
      const edge = await gatherWeek(cook, "2026-12-15");
      expect(edge.recipeCount).toBe(0);
      const first = await gatherWeek(cook, "2026-12-13");
      expect(first.recipeCount).toBe(1);
      expect((await gatherWeek(cook, "2026-12-19")).recipeCount).toBe(1);
      // The last day of the seven is included; the day after is not.
      expect((await gatherWeek(cook, "2026-12-16")).recipeCount).toBe(1);
      expect((await gatherWeek(cook, "2026-12-23")).recipeCount).toBe(0);
    });
  });

  describe("pantry", () => {
    it("is remembered per item across weeks and for every row of the same item", async () => {
      const cook = await freshCook();
      const weekA = "2027-01-04";
      const weekB = "2027-01-11";
      const a = await create(cook, "Saffron rice", [
        "1 tsp saffron",
        "200 g saffron",
        "1 cup rice",
      ]);
      await plan(cook, a.id, "2027-01-04");
      await plan(cook, a.id, "2027-01-12");
      const listA = await gatherWeek(cook, weekA);
      const saffron = byKey(listA, "saffron");
      expect(saffron).toHaveLength(2);
      expect(saffron.every((i: any) => !i.inPantry)).toBe(true);

      const marked = await call(cook, "PATCH", `/v1/gather/items/${saffron[0].id}`, {
        inPantry: true,
      });
      expect(marked.status).toBe(200);
      expect(marked.body.inPantry).toBe(true);

      // The other row with the same key, and other items, in the same week.
      const afterA = await gatherWeek(cook, weekA);
      expect(byKey(afterA, "saffron").every((i: any) => i.inPantry)).toBe(true);
      expect(byKey(afterA, "rice")[0].inPantry).toBe(false);
      // Another week, a different gathered row for the same key.
      const afterB = await gatherWeek(cook, weekB);
      expect(byKey(afterB, "saffron")).toHaveLength(2);
      expect(byKey(afterB, "saffron").every((i: any) => i.inPantry)).toBe(true);
      // A manual item with the same key picks it up too.
      const manual = await call(cook, "POST", `/v1/gather/${weekB}/items`, {
        line: "1 pinch saffron",
      });
      expect(manual.body.inPantry).toBe(true);
      // Pantry survives a regenerate and doesn't change the check.
      expect(byKey(await gatherWeek(cook, weekA), "saffron")[0].checked).toBe(false);

      // Marking twice is fine.
      expect(
        (await call(cook, "PATCH", `/v1/gather/items/${saffron[1].id}`, { inPantry: true })).body
          .inPantry,
      ).toBe(true);

      // Un-marking removes it everywhere.
      const unmarked = await call(cook, "PATCH", `/v1/gather/items/${saffron[1].id}`, {
        inPantry: false,
      });
      expect(unmarked.body.inPantry).toBe(false);
      expect(byKey(await gatherWeek(cook, weekA), "saffron").some((i: any) => i.inPantry)).toBe(
        false,
      );
      expect(byKey(await gatherWeek(cook, weekB), "saffron").some((i: any) => i.inPantry)).toBe(
        false,
      );
    });

    it("is private to the cook", async () => {
      const cook = await freshCook();
      const other = await freshCook();
      const recipe = await create(cook, "Mine", ["1 tsp turmeric"]);
      const theirs = await create(other, "Theirs", ["1 tsp turmeric"]);
      await plan(cook, recipe.id, "2027-02-01");
      await plan(other, theirs.id, "2027-02-01");
      const item = byKey(await gatherWeek(cook, "2027-02-01"), "turmeric")[0];
      await call(cook, "PATCH", `/v1/gather/items/${item.id}`, { inPantry: true });
      expect(byKey(await gatherWeek(other, "2027-02-01"), "turmeric")[0].inPantry).toBe(false);
    });

    it("checking and un-checking an item leaves its pantry mark alone", async () => {
      const cook = await freshCook();
      const manual = (await call(cook, "POST", `/v1/gather/2027-02-08/items`, { line: "2 limes" }))
        .body;
      await call(cook, "PATCH", `/v1/gather/items/${manual.id}`, { inPantry: true });
      const checked = await call(cook, "PATCH", `/v1/gather/items/${manual.id}`, { checked: true });
      expect(checked.body).toMatchObject({ checked: true, inPantry: true });
      const unchecked = await call(cook, "PATCH", `/v1/gather/items/${manual.id}`, {
        checked: false,
      });
      expect(unchecked.body).toMatchObject({ checked: false, inPantry: true });
      // An empty update changes nothing.
      expect((await call(cook, "PATCH", `/v1/gather/items/${manual.id}`, {})).body).toMatchObject({
        checked: false,
        inPantry: true,
      });
    });
  });

  describe("ownership", () => {
    it("keeps ada's list and items away from bob", async () => {
      const week = "2027-03-01";
      const recipe = await create(ada, "Ada's soup", ["2 carrots"]);
      await plan(ada, recipe.id, "2027-03-02");
      const mine = await call(ada, "POST", `/v1/gather/${week}/items`, { line: "2 lemons" });
      const list = await gatherWeek(ada, week);
      const gathered = byKey(list, "carrot")[0];
      expect(list.items).toHaveLength(2);

      // Bob sees an empty list for the same week.
      expect(await gatherWeek(bob, week)).toEqual({ weekStart: week, recipeCount: 0, items: [] });

      for (const id of [gathered.id, mine.body.id]) {
        expect((await call(bob, "PATCH", `/v1/gather/items/${id}`, { checked: true })).status).toBe(
          404,
        );
        expect(
          (await call(bob, "PATCH", `/v1/gather/items/${id}`, { inPantry: true })).status,
        ).toBe(404);
        expect((await call(bob, "DELETE", `/v1/gather/items/${id}`)).status).toBe(404);
      }
      // Bob's attempts changed nothing for ada, and left no pantry mark.
      const unchanged = await gatherWeek(ada, week);
      expect(unchanged.items.map((i: any) => [i.id, i.checked, i.inPantry])).toEqual(
        list.items.map((i: any) => [i.id, false, false]),
      );
      // Bob's own manual items don't reach ada.
      await call(bob, "POST", `/v1/gather/${week}/items`, { line: "bob's bread" });
      expect((await gatherWeek(ada, week)).items).toHaveLength(2);
      expect((await gatherWeek(bob, week)).items).toHaveLength(1);
    });

    it("answers 404 for an unknown id and 400 for a malformed one", async () => {
      const missing = "00000000-0000-4000-8000-000000000000";
      expect(
        (await call(ada, "PATCH", `/v1/gather/items/${missing}`, { checked: true })).status,
      ).toBe(404);
      expect((await call(ada, "DELETE", `/v1/gather/items/${missing}`)).status).toBe(404);
      expect((await call(ada, "PATCH", `/v1/gather/items/nope`, { checked: true })).status).toBe(
        400,
      );
      expect(
        (await call(ada, "PATCH", `/v1/gather/items/${missing}`, { checked: "yes" })).status,
      ).toBe(400);
    });

    it("never gathers another cook's recipes, even in the same week", async () => {
      const week = "2027-03-08";
      const a = await create(ada, "Ada only", ["1 cup quinoa"]);
      const b = await create(bob, "Bob only", ["1 cup farro"]);
      await plan(ada, a.id, "2027-03-08");
      await plan(bob, b.id, "2027-03-08");
      const adaList = await gatherWeek(ada, week);
      const bobList = await gatherWeek(bob, week);
      expect(adaList.items.map((i: any) => i.itemKey)).toEqual(["quinoa"]);
      expect(bobList.items.map((i: any) => i.itemKey)).toEqual(["farro"]);
    });
  });
});
