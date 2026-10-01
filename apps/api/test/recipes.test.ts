import { copy, parseIngredientLine, type RecipeInput } from "@cauldron/shared";
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

describe("recipes", () => {
  it("requires a session", async () => {
    const res = await api.send("/v1/recipes");
    expect(res.status).toBe(401);
  });

  it("creates and reads back a recipe with structured ingredients, steps and tags", async () => {
    const created = await create(ada);
    expect(created.title).toBe("Weeknight dal");
    expect(created.ingredients).toHaveLength(3);
    expect(created.ingredients[0]).toMatchObject({
      quantity: { min: 1, max: null },
      unit: "cup",
      item: "red lentils",
      itemKey: "red lentil",
      original: "1 cup red lentils",
    });
    expect(created.ingredients[1].note).toBe("minced");
    expect(created.steps.map((s: { text: string }) => s.text)).toEqual([
      "Rinse the lentils.",
      "Simmer 25 minutes.",
    ]);
    expect(created.tags.map((t: { name: string }) => t.name)).toEqual(["Indian", "Vegetarian"]);
    expect(created.deletedAt).toBeNull();

    const got = await call(ada, "GET", `/v1/recipes/${created.id}`);
    expect(got.status).toBe(200);
    expect(got.body).toEqual(created);
  });

  it("rejects invalid input with the error shape", async () => {
    const res = await call(ada, "POST", "/v1/recipes", input({ title: "   " }));
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("invalid_request");
    const badUrl = await call(
      ada,
      "POST",
      "/v1/recipes",
      input({ sourceUrl: "javascript:alert(1)" }),
    );
    expect(badUrl.status).toBe(400);
    const badId = await call(ada, "GET", "/v1/recipes/not-a-uuid");
    expect(badId.status).toBe(400);
    // Bigger than the quantity column holds: a 400, not a database error.
    const [line] = lines("2 cups flour");
    const huge = await call(
      ada,
      "POST",
      "/v1/recipes",
      input({ ingredients: [{ ...line!, quantity: { min: 1e12, max: null } }] }),
    );
    expect(huge.status).toBe(400);
    expect(huge.body.error.code).toBe("invalid_request");
  });

  it("stores blank optional text as null and trims", async () => {
    const created = await create(ada, { title: "  Toast  ", description: "  ", notes: "" });
    expect(created.title).toBe("Toast");
    expect(created.description).toBeNull();
    expect(created.notes).toBeNull();
  });

  it("replaces ingredients, steps and tags on update", async () => {
    const created = await create(ada);
    const res = await call(
      ada,
      "PUT",
      `/v1/recipes/${created.id}`,
      input({
        title: "Better dal",
        tags: ["indian", "Quick"],
        ingredients: [
          { ...lines("For the tadka")[0]!, ...lines("2 tbsp ghee")[0]!, section: "For the tadka" },
        ],
        steps: [{ section: null, text: "Fry the spices.", timerSeconds: null }],
      }),
    );
    expect(res.status).toBe(200);
    expect(res.body.title).toBe("Better dal");
    expect(res.body.ingredients).toHaveLength(1);
    expect(res.body.ingredients[0]).toMatchObject({ section: "For the tadka", item: "ghee" });
    expect(res.body.steps).toHaveLength(1);
    // Tags match case-insensitively, so "indian" reuses the existing "Indian".
    expect(res.body.tags.map((t: { name: string }) => t.name)).toEqual(["Indian", "Quick"]);
  });

  it("never shows one user's recipe to another", async () => {
    const created = await create(ada, { title: "Ada's secret soup" });
    const paths = [
      ["GET", `/v1/recipes/${created.id}`],
      ["PUT", `/v1/recipes/${created.id}`, input()],
      ["DELETE", `/v1/recipes/${created.id}`],
      ["POST", `/v1/recipes/${created.id}/restore`],
      ["POST", `/v1/recipes/${created.id}/duplicate`],
      ["POST", `/v1/recipes/${created.id}/cooked`, { on: "2026-10-01" }],
    ] as const;
    for (const [method, path, body] of paths) {
      const res = await call(bob, method, path, body);
      expect(res.status, `${method} ${path}`).toBe(404);
      expect(res.body.error.code).toBe("not_found");
    }
    const list = await call(bob, "GET", "/v1/recipes?limit=100");
    expect(list.body.items.map((r: { id: string }) => r.id)).not.toContain(created.id);
    const search = await call(bob, "GET", "/v1/recipes/search?q=secret");
    expect(search.body).toEqual([]);
    const tags = await call(bob, "GET", "/v1/tags");
    expect(tags.body).toEqual([]);
    // Filtering by Ada's tag id finds nothing for Bob.
    const adaTags = await call(ada, "GET", "/v1/tags");
    const byAdasTag = await call(bob, "GET", `/v1/recipes?tag=${adaTags.body[0].id}`);
    expect(byAdasTag.status).toBe(200);
    expect(byAdasTag.body.items).toEqual([]);
    // Ada's recipe is untouched.
    const mine = await call(ada, "GET", `/v1/recipes/${created.id}`);
    expect(mine.body.title).toBe("Ada's secret soup");
  });

  it("banishes, hides, and restores", async () => {
    const created = await create(ada, { title: "Banish me" });
    const banished = await call(ada, "DELETE", `/v1/recipes/${created.id}`);
    expect(banished.status).toBe(200);
    expect(banished.body.deletedAt).not.toBeNull();
    expect((await call(ada, "GET", `/v1/recipes/${created.id}`)).status).toBe(404);
    expect((await call(ada, "DELETE", `/v1/recipes/${created.id}`)).status).toBe(404);
    const list = await call(ada, "GET", "/v1/recipes?limit=100");
    expect(list.body.items.map((r: { id: string }) => r.id)).not.toContain(created.id);

    const restored = await call(ada, "POST", `/v1/recipes/${created.id}/restore`);
    expect(restored.status).toBe(200);
    expect(restored.body.deletedAt).toBeNull();
    expect((await call(ada, "GET", `/v1/recipes/${created.id}`)).status).toBe(200);
  });

  it("duplicates a recipe with its ingredients, steps and tags", async () => {
    const created = await create(ada, { title: "Fork me", sourceUrl: "https://example.com/r" });
    const res = await call(ada, "POST", `/v1/recipes/${created.id}/duplicate`);
    expect(res.status).toBe(200);
    expect(res.body.id).not.toBe(created.id);
    expect(res.body.title).toBe(copy.recipes.copyOf("Fork me").text);
    expect(res.body.sourceUrl).toBe("https://example.com/r");
    expect(res.body.ingredients).toEqual(created.ingredients);
    expect(res.body.steps).toEqual(created.steps);
    expect(res.body.tags).toEqual(created.tags);
    expect(res.body.lastCookedOn).toBeNull();
  });

  it("records cooked days and keeps the latest", async () => {
    const created = await create(ada, { title: "Cook me" });
    const first = await call(ada, "POST", `/v1/recipes/${created.id}/cooked`, { on: "2026-09-20" });
    expect(first.status).toBe(200);
    expect(first.body.lastCookedOn).toBe("2026-09-20");
    // An earlier day doesn't move "last cooked" back.
    const earlier = await call(ada, "POST", `/v1/recipes/${created.id}/cooked`, {
      on: "2026-09-01",
    });
    expect(earlier.body.lastCookedOn).toBe("2026-09-20");
    const bad = await call(ada, "POST", `/v1/recipes/${created.id}/cooked`, { on: "yesterday" });
    expect(bad.status).toBe(400);
    const impossible = await call(ada, "POST", `/v1/recipes/${created.id}/cooked`, {
      on: "2026-02-31",
    });
    expect(impossible.status).toBe(400);
    // The same day twice is one entry, and still fine.
    const again = await call(ada, "POST", `/v1/recipes/${created.id}/cooked`, { on: "2026-09-20" });
    expect(again.status).toBe(200);
  });
});

describe("listing", () => {
  let cookie: string;
  beforeAll(async () => {
    cookie = await signUpVerified("lister@example.com");
    for (const title of ["banana bread", "Apple crumble", "carrot cake", "Date squares"]) {
      await create(cookie, { title, tags: title.includes("cake") ? ["Cake"] : ["Bake"] });
    }
  });

  const pages = async (query: string) => {
    const titles: Array<string> = [];
    let cursor: string | null = null;
    for (let i = 0; i < 10; i++) {
      const sep = query ? "&" : "";
      const res: Res = await call(
        cookie,
        "GET",
        `/v1/recipes?limit=1${sep}${query}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`,
      );
      expect(res.status).toBe(200);
      titles.push(...res.body.items.map((r: { title: string }) => r.title));
      cursor = res.body.nextCursor;
      if (!cursor) break;
    }
    return titles;
  };

  it("pages newest first by default", async () => {
    expect(await pages("")).toEqual([
      "Date squares",
      "carrot cake",
      "Apple crumble",
      "banana bread",
    ]);
  });

  it("sorts by title, case-insensitively", async () => {
    expect(await pages("sort=title")).toEqual([
      "Apple crumble",
      "banana bread",
      "carrot cake",
      "Date squares",
    ]);
  });

  it("sorts by last cooked, never-cooked last", async () => {
    const list = await call(cookie, "GET", "/v1/recipes?sort=title");
    const [apple, banana] = list.body.items;
    await call(cookie, "POST", `/v1/recipes/${banana.id}/cooked`, { on: "2026-09-02" });
    await call(cookie, "POST", `/v1/recipes/${apple.id}/cooked`, { on: "2026-09-01" });
    const titles = await pages("sort=lastCooked");
    // Never-cooked recipes follow, newest id first, each exactly once.
    expect(titles.slice(0, 2)).toEqual(["banana bread", "Apple crumble"]);
    expect(titles.slice(2).sort()).toEqual(["Date squares", "carrot cake"]);
    expect(new Set(titles).size).toBe(4);
  });

  it("pages through titles that tie when lowercased", async () => {
    const tied = await signUpVerified("tied@example.com");
    for (const title of ["Soup", "soup", "SOUP", "Stew"]) await create(tied, { title });
    const seen: Array<string> = [];
    let cursor: string | null = null;
    do {
      const res: Res = await call(
        tied,
        "GET",
        `/v1/recipes?limit=1&sort=title${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`,
      );
      seen.push(...res.body.items.map((r: { id: string }) => r.id));
      cursor = res.body.nextCursor;
    } while (cursor);
    expect(seen).toHaveLength(4);
    expect(new Set(seen).size).toBe(4);
  });

  it("filters by tag", async () => {
    const tags = await call(cookie, "GET", "/v1/tags");
    const cake = tags.body.find((t: { name: string }) => t.name === "Cake");
    expect(cake.recipeCount).toBe(1);
    expect(await pages(`tag=${cake.id}`)).toEqual(["carrot cake"]);
  });

  it("rejects a cursor from another sort, or a tampered one", async () => {
    const first = await call(cookie, "GET", "/v1/recipes?limit=1");
    const cursor = encodeURIComponent(first.body.nextCursor);
    const wrongSort = await call(cookie, "GET", `/v1/recipes?limit=1&sort=title&cursor=${cursor}`);
    expect(wrongSort.status).toBe(400);
    const junk = await call(cookie, "GET", "/v1/recipes?cursor=bm9wZQ");
    expect(junk.status).toBe(400);
    expect(junk.body.error.code).toBe("invalid_request");
    // Well-formed cursors with keys Postgres can't read are a 400 too.
    const forge = (s: string, k: string) =>
      Buffer.from(JSON.stringify({ s, k, i: "00000000-0000-4000-8000-000000000000" })).toString(
        "base64url",
      );
    for (const [sort, key] of [
      ["recent", "Tue Oct 1 2026"],
      ["lastCooked", "2026-02-31"],
    ] as const) {
      const res = await call(cookie, "GET", `/v1/recipes?sort=${sort}&cursor=${forge(sort, key)}`);
      expect(res.status, sort).toBe(400);
    }
  });
});

describe("search", () => {
  let cookie: string;
  beforeAll(async () => {
    cookie = await signUpVerified("searcher@example.com");
    await create(cookie, {
      title: "Chicken tikka masala",
      tags: ["Curry"],
      ingredients: lines("500 g chicken thighs", "1 cup yogurt"),
    });
    await create(cookie, {
      title: "Tomato soup",
      tags: ["Soup"],
      ingredients: lines("2 lb tomatoes", "1 onion"),
    });
    await create(cookie, {
      title: "Spaghetti bolognese",
      tags: ["Pasta"],
      ingredients: lines("1 lb ground beef", "400 g canned tomatoes"),
    });
  });

  const titles = (res: Res) => res.body.map((r: { title: string }) => r.title).sort();

  it("matches the title as you type", async () => {
    expect(titles(await call(cookie, "GET", "/v1/recipes/search?q=chick"))).toEqual([
      "Chicken tikka masala",
    ]);
    // Substring of a word in the title.
    expect(titles(await call(cookie, "GET", "/v1/recipes/search?q=olog"))).toEqual([
      "Spaghetti bolognese",
    ]);
  });

  it("matches ingredients and tags", async () => {
    expect(titles(await call(cookie, "GET", "/v1/recipes/search?q=tomatoes"))).toEqual([
      "Spaghetti bolognese",
      "Tomato soup",
    ]);
    expect(titles(await call(cookie, "GET", "/v1/recipes/search?q=curry"))).toEqual([
      "Chicken tikka masala",
    ]);
    expect(titles(await call(cookie, "GET", "/v1/recipes/search?q=yogurt%20chicken"))).toEqual([
      "Chicken tikka masala",
    ]);
  });

  it("puts a title match first", async () => {
    const res = await call(cookie, "GET", "/v1/recipes/search?q=tomato");
    expect(res.body[0].title).toBe("Tomato soup");
  });

  it("handles punctuation and empty queries", async () => {
    expect((await call(cookie, "GET", "/v1/recipes/search?q=%27%26%7C!")).body).toEqual([]);
    expect((await call(cookie, "GET", "/v1/recipes/search?q=")).body).toEqual([]);
    expect((await call(cookie, "GET", "/v1/recipes/search?q=100%25")).status).toBe(200);
  });

  it("filters the list with q", async () => {
    const res = await call(cookie, "GET", "/v1/recipes?q=soup");
    expect(res.body.items.map((r: { title: string }) => r.title)).toEqual(["Tomato soup"]);
  });

  it("follows a tag rename", async () => {
    const tags = await call(cookie, "GET", "/v1/tags");
    const pasta = tags.body.find((t: { name: string }) => t.name === "Pasta");
    const renamed = await call(cookie, "PATCH", `/v1/tags/${pasta.id}`, { name: "Noodles" });
    expect(renamed.status).toBe(200);
    expect(renamed.body).toMatchObject({ name: "Noodles", recipeCount: 1 });
    expect(titles(await call(cookie, "GET", "/v1/recipes/search?q=noodles"))).toEqual([
      "Spaghetti bolognese",
    ]);
  });
});

describe("tags", () => {
  it("refuses a rename onto an existing name, and another user's tag", async () => {
    const cookie = await signUpVerified("tagger@example.com");
    await create(cookie, { tags: ["Lunch", "Dinner"] });
    const tags = (await call(cookie, "GET", "/v1/tags")).body;
    const lunch = tags.find((t: { name: string }) => t.name === "Lunch");
    const clash = await call(cookie, "PATCH", `/v1/tags/${lunch.id}`, { name: "dinner" });
    expect(clash.status).toBe(409);
    expect(clash.body.error).toEqual({ code: "conflict", message: copy.recipes.tagNameTaken.text });
    // Changing only the case of its own name is fine.
    const recase = await call(cookie, "PATCH", `/v1/tags/${lunch.id}`, { name: "LUNCH" });
    expect(recase.status).toBe(200);
    const theirs = await call(bob, "PATCH", `/v1/tags/${lunch.id}`, { name: "Mine now" });
    expect(theirs.status).toBe(404);
  });

  it("counts only live recipes", async () => {
    const cookie = await signUpVerified("counter@example.com");
    const a = await create(cookie, { tags: ["Soup"] });
    await create(cookie, { tags: ["Soup"] });
    await call(cookie, "DELETE", `/v1/recipes/${a.id}`);
    const tags = (await call(cookie, "GET", "/v1/tags")).body;
    expect(tags).toEqual([expect.objectContaining({ name: "Soup", recipeCount: 1 })]);
  });
});
