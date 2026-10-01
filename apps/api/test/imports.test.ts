import { schema } from "@cauldron/db";
import { copy, type ImportDraft, parseIngredientLine, type RecipeInput } from "@cauldron/shared";
import { eq } from "drizzle-orm";
import { Effect, Layer } from "effect";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { Routes } from "../src/App.ts";
import { Db } from "../src/Db.ts";
import { ImportWorker } from "../src/Imports.ts";
import { emptyExtracted } from "../src/imports/Extracted.ts";
import { type ExtractInput, RecipeExtractor } from "../src/imports/RecipeExtractor.ts";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

const PASSWORD = "correct-horse-1";

const PASTED = `Weeknight dal

A quick red lentil dal.

Serves 4
Prep: 10 mins | Cook: 30 mins

Ingredients
- 1 cup red lentils, rinsed
- 1 onion, finely chopped
- 2 tsp ground cumin

Method
1. Fry the onion until soft.
2. Add the lentils, cumin and 3 cups water.
3. Simmer for 25 minutes.`;

// A paste with no headings, which the text reader can't lay out by itself.
const MESSY = "made this dal last night, lentils + onion + cumin, simmer it all, so good";

// The fake model: a recipe for MESSY, nothing for "no recipe here", and a
// job that never finishes for "hang".
const calls: Array<ExtractInput> = [];
const fakeModel = RecipeExtractor.layerTest((input) => {
  calls.push(input);
  if (input.text.includes("hang")) return Effect.never;
  if (input.text.includes("no recipe here")) return Effect.succeed("missing" as const);
  return Effect.succeed({
    ...emptyExtracted,
    title: "Last night's dal",
    servings: 2,
    ingredients: [
      { line: "1 cup red lentils", section: null, unsure: false },
      { line: "some cumin", section: null, unsure: true },
    ],
    steps: [{ text: "Simmer it all.", section: null, unsure: false }],
    unsure: ["servings"],
  });
});

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
  api = makeAuthApi({}, Layer.merge(Routes, ImportWorker), {}, fakeModel);
  ada = await signUpVerified("ada@example.com");
  bob = await signUpVerified("bob@example.com");
});
afterAll(() => api.dispose());

const call = async (cookie: string, method: string, path: string, body?: unknown) => {
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

/** Polls a job until it's no longer queued or running. */
const settled = async (cookie: string, id: string) => {
  for (let i = 0; i < 500; i++) {
    const res = await call(cookie, "GET", `/v1/imports/${id}`);
    if (res.status !== 200 || !["queued", "running"].includes(res.body.status)) return res;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("import never settled");
};

/** What the editor would send after the cook accepts the draft as it is. */
const reviewed = (draft: ImportDraft): RecipeInput => ({
  title: draft.title,
  description: draft.description,
  servings: draft.servings,
  prepMinutes: draft.prepMinutes,
  cookMinutes: draft.cookMinutes,
  totalMinutes: draft.totalMinutes,
  sourcePlatform: draft.sourcePlatform,
  sourceUrl: draft.sourceUrl,
  sourceAuthor: draft.sourceAuthor,
  notes: draft.notes,
  photoKey: draft.photoKey,
  tags: [...draft.tags],
  ingredients: draft.ingredients.map((i) => ({
    ...parseIngredientLine(i.line),
    section: i.section,
  })),
  steps: draft.steps.map((s) => ({ section: s.section, text: s.text, timerSeconds: null })),
});

const jobRow = (id: string) =>
  api.run(
    Effect.gen(function* () {
      const db = yield* Db;
      const [row] = yield* db.use((d) =>
        d.select().from(schema.importJob).where(eq(schema.importJob.id, id)),
      );
      return row!;
    }),
  );

describe("distilling pasted text", () => {
  it("reads a laid-out paste without the model, then saves the reviewed draft", async () => {
    const before = calls.length;
    const started = await call(ada, "POST", "/v1/imports", { text: PASTED });
    expect(started.status).toBe(200);
    expect(started.body).toMatchObject({ status: "queued", source: "text", draft: null });

    const done = await settled(ada, started.body.id);
    expect(done.body.status).toBe("done");
    const draft = done.body.draft as ImportDraft;
    expect(draft).toMatchObject({
      title: "Weeknight dal",
      description: "A quick red lentil dal.",
      servings: 4,
      prepMinutes: 10,
      cookMinutes: 30,
      sourcePlatform: "text",
      sourceUrl: null,
      unsure: [],
    });
    expect(draft.ingredients.map((i) => i.line)).toEqual([
      "1 cup red lentils, rinsed",
      "1 onion, finely chopped",
      "2 tsp ground cumin",
    ]);
    expect(draft.steps.map((s) => s.text)).toEqual([
      "Fry the onion until soft.",
      "Add the lentils, cumin and 3 cups water.",
      "Simmer for 25 minutes.",
    ]);
    expect(calls.length).toBe(before);
    const row = await jobRow(started.body.id);
    expect(row).toMatchObject({ extractor: "text", model: null, inputTokens: null });

    const saved = await call(ada, "POST", `/v1/imports/${started.body.id}/recipe`, reviewed(draft));
    expect(saved.status).toBe(200);
    expect(saved.body).toMatchObject({ title: "Weeknight dal", sourcePlatform: "text" });
    expect(saved.body.ingredients[0]).toMatchObject({
      quantity: { min: 1, max: null },
      unit: "cup",
    });

    const after = await call(ada, "GET", `/v1/imports/${started.body.id}`);
    expect(after.body).toMatchObject({ status: "saved", recipeId: saved.body.id });

    const again = await call(ada, "POST", `/v1/imports/${started.body.id}/recipe`, reviewed(draft));
    expect(again.status).toBe(409);
    expect(again.body.error.message).toBe(copy.imports.alreadySaved.text);
  });

  it("sends messy text to the model and logs its cost", async () => {
    const started = await call(ada, "POST", "/v1/imports", { text: MESSY });
    const done = await settled(ada, started.body.id);
    expect(done.body.status).toBe("done");
    expect(calls.at(-1)).toEqual({ text: MESSY, kind: "text" });
    expect(done.body.draft).toMatchObject({
      title: "Last night's dal",
      servings: 2,
      unsure: ["servings"],
      ingredients: [
        { line: "1 cup red lentils", unsure: false },
        { line: "some cumin", unsure: true },
      ],
    });
    const row = await jobRow(started.body.id);
    expect(row).toMatchObject({
      extractor: "model",
      model: "fake",
      inputTokens: MESSY.length,
      outputTokens: 100,
      attempts: 1,
    });
  });

  it("fails with a plain message when there's no recipe", async () => {
    const started = await call(ada, "POST", "/v1/imports", { text: "no recipe here, just chat" });
    const done = await settled(ada, started.body.id);
    expect(done.body).toMatchObject({
      status: "failed",
      draft: null,
      failure: { code: "noRecipe", message: copy.imports.noRecipeInText.text },
    });
    const save = await call(ada, "POST", `/v1/imports/${started.body.id}/recipe`, {});
    expect(save.status).toBe(400);
  });

  it("stops a running job when it's cancelled", async () => {
    const started = await call(ada, "POST", "/v1/imports", { text: "hang on, this takes a while" });
    for (let i = 0; i < 200; i++) {
      const res = await call(ada, "GET", `/v1/imports/${started.body.id}`);
      if (res.body.status === "running") break;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    const cancelled = await call(ada, "DELETE", `/v1/imports/${started.body.id}`);
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.status).toBe("cancelled");
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect((await call(ada, "GET", `/v1/imports/${started.body.id}`)).body.status).toBe(
      "cancelled",
    );
    // The workers are free again.
    const next = await settled(
      ada,
      (await call(ada, "POST", "/v1/imports", { text: PASTED })).body.id,
    );
    expect(next.body.status).toBe("done");
  });
});

describe("import jobs", () => {
  it("takes a link or text, not both or neither", async () => {
    expect((await call(ada, "POST", "/v1/imports", {})).status).toBe(400);
    expect(
      (await call(ada, "POST", "/v1/imports", { url: "https://example.com/dal", text: "dal" }))
        .status,
    ).toBe(400);
    expect((await call(ada, "POST", "/v1/imports", { url: "ftp://example.com/dal" })).status).toBe(
      400,
    );
  });

  it("detects the source from the link", async () => {
    const insta = await call(ada, "POST", "/v1/imports", {
      url: "https://www.instagram.com/reel/abc123/",
    });
    const tiktok = await call(ada, "POST", "/v1/imports", {
      url: "https://vm.tiktok.com/ZM123/",
    });
    const web = await call(ada, "POST", "/v1/imports", { url: "https://example.com/dal" });
    expect([insta.body.source, tiktok.body.source, web.body.source]).toEqual([
      "instagram",
      "tiktok",
      "web",
    ]);
  });

  it("warns when the same link is already in the box", async () => {
    const link = "https://example.com/recipes/dal";
    const recipe = await call(ada, "POST", "/v1/recipes", {
      ...reviewed({
        title: "Dal",
        description: null,
        servings: null,
        prepMinutes: null,
        cookMinutes: null,
        totalMinutes: null,
        sourcePlatform: "web",
        sourceUrl: link,
        sourceAuthor: null,
        siteName: null,
        notes: null,
        photoKey: null,
        tags: [],
        ingredients: [],
        steps: [],
        unsure: [],
      }),
    });
    expect(recipe.status).toBe(200);
    // Tracking parameters and a trailing slash don't hide it.
    const started = await call(ada, "POST", "/v1/imports", {
      url: `${link}/?utm_source=share#jump`,
    });
    expect(started.body.duplicateOf).toEqual({ id: recipe.body.id, title: "Dal" });
    // Bob has no such recipe.
    const bobs = await call(bob, "POST", "/v1/imports", { url: link });
    expect(bobs.body.duplicateOf).toBeNull();
  });

  it("keeps each cook's jobs to themselves", async () => {
    const started = await call(ada, "POST", "/v1/imports", { text: PASTED });
    expect((await call(bob, "GET", `/v1/imports/${started.body.id}`)).status).toBe(404);
    expect((await call(bob, "DELETE", `/v1/imports/${started.body.id}`)).status).toBe(404);
    await settled(ada, started.body.id);
    const done = await call(ada, "GET", `/v1/imports/${started.body.id}`);
    expect(
      (await call(bob, "POST", `/v1/imports/${started.body.id}/recipe`, reviewed(done.body.draft)))
        .status,
    ).toBe(404);
  });
});
