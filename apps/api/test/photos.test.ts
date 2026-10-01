import { schema } from "@cauldron/db";
import { copy, parseIngredientLine, type RecipeInput } from "@cauldron/shared";
import { assert, layer } from "@effect/vitest";
import { eq, inArray } from "drizzle-orm";
import { Effect, Layer, Ref } from "effect";
import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { AppConfig } from "../src/AppConfig.ts";
import { Db } from "../src/Db.ts";
import { Photos, uploadKey, variantKey } from "../src/Photos.ts";
import { RemoteFetch } from "../src/RemoteFetch.ts";
import { Storage, StorageObjects } from "../src/Storage.ts";
import { type AuthApi, cookieOf, makeAuthApi } from "./auth-helpers.ts";
import { WEB_ORIGIN } from "./helpers.ts";

const PASSWORD = "correct-horse-1";

// Generated, not checked in.
const noise = (width: number, height: number) => ({
  create: { width, height, channels: 3 as const, background: { r: 200, g: 90, b: 40 } },
});
const bigJpeg = () => sharp(noise(2400, 1600)).jpeg().toBuffer();
const smallPng = () => sharp(noise(40, 30)).png().toBuffer();
const gifBytes = () => sharp(noise(10, 10)).gif().toBuffer();

let api: AuthApi;
let ada: string;
let bob: string;
let jpeg: Buffer;
let png: Buffer;
let gif: Buffer;

const signUpVerified = async (email: string) => {
  const before = (await api.outbox()).length;
  await api.post("/v1/auth/sign-up/email", { email, password: PASSWORD, name: "Cook" });
  const sent = (await api.waitForOutbox(before + 1)).slice(before).filter((m) => m.to === email);
  const cookie = cookieOf(await api.send(api.linkIn(sent[0]!)));
  if (!cookie) throw new Error("verification didn't sign in");
  return cookie;
};

beforeAll(async () => {
  [jpeg, png, gif] = await Promise.all([bigJpeg(), smallPng(), gifBytes()]);
  api = makeAuthApi({}, undefined, {
    "https://cdn.example.com/dal.png": { bytes: new Uint8Array(png), contentType: "image/png" },
  });
  ada = await signUpVerified("ada@example.com");
  bob = await signUpVerified("bob@example.com");
});
afterAll(() => api.dispose());

const call = async (cookie: string | null, method: string, path: string, body?: unknown) => {
  const res = await api.send(path, {
    method,
    headers: {
      ...(cookie ? { cookie } : {}),
      origin: WEB_ORIGIN,
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
};

const startUpload = (cookie: string | null, contentType: string, size: number) =>
  call(cookie, "POST", "/v1/photos/uploads", { contentType, size });

const put = (cookie: string | null, id: string, bytes: Uint8Array) =>
  api.send(`/v1/photos/uploads/${id}`, {
    method: "PUT",
    headers: {
      ...(cookie ? { cookie } : {}),
      origin: WEB_ORIGIN,
      "content-type": "application/octet-stream",
    },
    body: bytes as BodyInit,
  });

const finish = (cookie: string | null, uploadId: string) =>
  call(cookie, "POST", "/v1/photos", { uploadId });

/** The whole happy path: start, PUT, finish. */
const upload = async (cookie: string, bytes: Uint8Array, contentType = "image/jpeg") => {
  const started = await startUpload(cookie, contentType, bytes.byteLength);
  expect(started.status).toBe(200);
  const sent = await put(cookie, started.body.id, bytes);
  expect(sent.status).toBe(204);
  return finish(cookie, started.body.id);
};

const variant = (cookie: string | null, id: string, name: string) =>
  api.send(`/v1/photos/${id}/${name}`, { headers: cookie ? { cookie } : {} });

describe("photo upload flow", () => {
  it("starts an upload with an API URL and headers", async () => {
    const res = await startUpload(ada, "image/jpeg", jpeg.byteLength);
    expect(res.status).toBe(200);
    expect(res.body.url).toBe(`http://localhost:3000/v1/photos/uploads/${res.body.id}`);
    expect(res.body.headers).toEqual({ "content-type": "application/octet-stream" });
  });

  it("uploads, finishes and serves three WebP variants", async () => {
    const done = await upload(ada, jpeg);
    expect(done.status).toBe(200);
    expect(done.body.width).toBe(1920);
    expect(done.body.height).toBe(1280);

    for (const [name, width] of [
      ["thumb", 320],
      ["card", 800],
      ["full", 1920],
    ] as const) {
      const res = await variant(ada, done.body.id, name);
      expect(res.status).toBe(200);
      expect(res.headers.get("content-type")).toContain("image/webp");
      expect(res.headers.get("cache-control")).toContain("immutable");
      const meta = await sharp(Buffer.from(await res.arrayBuffer())).metadata();
      expect(meta.format).toBe("webp");
      expect(meta.width).toBe(width);
    }
  });

  it("doesn't enlarge small images", async () => {
    const done = await upload(ada, png, "image/png");
    expect(done.status).toBe(200);
    expect(done.body).toMatchObject({ width: 40, height: 30 });
  });

  it("refuses to finish the same upload twice", async () => {
    const started = await startUpload(ada, "image/png", png.byteLength);
    await put(ada, started.body.id, png);
    expect((await finish(ada, started.body.id)).status).toBe(200);
    const again = await finish(ada, started.body.id);
    expect(again.status).toBe(400);
    expect(again.body.error.message).toBe(copy.photos.uploadExpired.text);
  });

  it("refuses to finish an upload whose bytes never arrived", async () => {
    const started = await startUpload(ada, "image/png", 100);
    const res = await finish(ada, started.body.id);
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe(copy.photos.uploadExpired.text);
  });
});

describe("photo ownership and sessions", () => {
  it("hides one user's photo variants from another", async () => {
    const done = await upload(ada, png, "image/png");
    for (const name of ["thumb", "card", "full"]) {
      expect((await variant(bob, done.body.id, name)).status).toBe(404);
    }
    expect((await variant(ada, done.body.id, "thumb")).status).toBe(200);
  });

  it("returns 404 for a photo that doesn't exist", async () => {
    expect((await variant(ada, crypto.randomUUID(), "thumb")).status).toBe(404);
  });

  it("refuses another user's upload id for PUT and finish", async () => {
    const started = await startUpload(ada, "image/png", png.byteLength);
    expect((await put(bob, started.body.id, png)).status).toBe(400);
    expect((await finish(bob, started.body.id)).status).toBe(400);
    // Ada's upload is untouched by Bob's attempts.
    expect((await put(ada, started.body.id, png)).status).toBe(204);
    expect((await finish(ada, started.body.id)).status).toBe(200);
  });

  it("requires a session everywhere", async () => {
    const id = crypto.randomUUID();
    expect((await startUpload(null, "image/png", 10)).status).toBe(401);
    expect((await put(null, id, png)).status).toBe(401);
    expect((await finish(null, id)).status).toBe(401);
    expect(
      (await call(null, "POST", "/v1/photos/from-url", { url: "https://x.test/a.png" })).status,
    ).toBe(401);
    expect((await variant(null, id, "thumb")).status).toBe(401);
  });
});

describe("photo bad input", () => {
  it("refuses bytes that aren't an image", async () => {
    const done = await upload(ada, new TextEncoder().encode("not an image at all"), "image/png");
    expect(done.status).toBe(400);
    expect(done.body.error.code).toBe("invalid_request");
    expect([copy.photos.couldntRead.text, copy.photos.unsupported.text]).toContain(
      done.body.error.message,
    );
  });

  it("refuses an empty body", async () => {
    const started = await startUpload(ada, "image/png", 1);
    const res = await put(ada, started.body.id, new Uint8Array());
    expect(res.status).toBe(400);
  });

  it("refuses unsupported content types and oversized files at the start", async () => {
    expect((await startUpload(ada, "image/gif", 100)).status).toBe(400);
    expect((await startUpload(ada, "image/png", 15 * 1024 * 1024 + 1)).status).toBe(400);
    expect((await startUpload(ada, "image/png", 0)).status).toBe(400);
    expect((await startUpload(ada, "image/png", 15 * 1024 * 1024)).status).toBe(200);
  });

  it("refuses GIF bytes uploaded as image/png", async () => {
    const done = await upload(ada, gif, "image/png");
    expect(done.status).toBe(400);
    expect(done.body.error.message).toBe(copy.photos.unsupported.text);
  });

  it("refuses a non-uuid upload id", async () => {
    expect((await put(ada, "not-a-uuid", png)).status).toBe(400);
    expect((await finish(ada, "not-a-uuid")).status).toBe(400);
  });
});

describe("photos on recipes", () => {
  const recipeInput = (photoKey: string | null): RecipeInput => ({
    title: "Photo dal",
    description: null,
    servings: 4,
    prepMinutes: null,
    cookMinutes: null,
    totalMinutes: null,
    sourcePlatform: "manual",
    sourceUrl: null,
    sourceAuthor: null,
    notes: null,
    photoKey,
    tags: [],
    ingredients: [{ ...parseIngredientLine("1 cup red lentils"), section: null }],
    steps: [{ section: null, text: "Simmer.", timerSeconds: null }],
  });

  it("saves my photo on a recipe, and a duplicate keeps it", async () => {
    const photo = await upload(ada, png, "image/png");
    const created = await call(ada, "POST", "/v1/recipes", recipeInput(photo.body.id));
    expect(created.status).toBe(200);
    expect(created.body.photoKey).toBe(photo.body.id);

    const got = await call(ada, "GET", `/v1/recipes/${created.body.id}`);
    expect(got.body.photoKey).toBe(photo.body.id);

    const copied = await call(ada, "POST", `/v1/recipes/${created.body.id}/duplicate`);
    expect(copied.status).toBe(200);
    expect(copied.body.id).not.toBe(created.body.id);
    expect(copied.body.photoKey).toBe(photo.body.id);
  });

  it("refuses another user's photo or a made-up id", async () => {
    const photo = await upload(ada, png, "image/png");
    const stolen = await call(bob, "POST", "/v1/recipes", recipeInput(photo.body.id));
    expect(stolen.status).toBe(400);
    const missing = await call(bob, "POST", "/v1/recipes", recipeInput(crypto.randomUUID()));
    expect(missing.status).toBe(400);

    const mine = await call(bob, "POST", "/v1/recipes", recipeInput(null));
    expect(mine.status).toBe(200);
    const swap = await call(bob, "PUT", `/v1/recipes/${mine.body.id}`, recipeInput(photo.body.id));
    expect(swap.status).toBe(400);
  });
});

describe("photos from a URL", () => {
  it("fetches a photo through RemoteFetch", async () => {
    const res = await call(ada, "POST", "/v1/photos/from-url", {
      url: "https://cdn.example.com/dal.png",
    });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ width: 40, height: 30 });
    expect((await variant(ada, res.body.id, "card")).status).toBe(200);
  });

  it("refuses a URL that can't be fetched", async () => {
    const res = await call(ada, "POST", "/v1/photos/from-url", {
      url: "https://cdn.example.com/missing.png",
    });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe(copy.photos.couldntFetch.text);
  });

  it("refuses a URL that isn't http(s)", async () => {
    const res = await call(ada, "POST", "/v1/photos/from-url", {
      url: "ftp://cdn.example.com/a.png",
    });
    expect(res.status).toBe(400);
  });
});

// Cleanup, on the service directly.
const DAY = 24 * 60 * 60 * 1000;
const PNG_URL = "https://cdn.example.com/a.png";

const cleanupLayer = Photos.layer.pipe(
  Layer.provideMerge(
    Layer.mergeAll(
      Db.layerTest,
      Storage.layerTest,
      RemoteFetch.layerTest({
        [PNG_URL]: {
          bytes: new Uint8Array(
            // A valid 1x1 PNG.
            Buffer.from(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
              "base64",
            ),
          ),
          contentType: "image/png",
        },
      }),
      AppConfig.layerTest(),
    ),
  ),
);

layer(cleanupLayer)("photo cleanup", (it) => {
  it.effect("removes stale uploads and unreferenced photos, keeps the rest", () =>
    Effect.gen(function* () {
      const db = yield* Db;
      const photos = yield* Photos;
      const objects = yield* StorageObjects;
      const storage = yield* Storage;
      const keys = () => Ref.get(objects).pipe(Effect.map((m) => [...m.keys()]));

      const ownerId = `u_${crypto.randomUUID()}`;
      yield* db.use((d) =>
        d
          .insert(schema.user)
          .values({ id: ownerId, name: "Test", email: `${ownerId}@example.test` }),
      );

      const orphan = yield* photos.fromUrl(ownerId as never, PNG_URL);
      const used = yield* photos.fromUrl(ownerId as never, PNG_URL);
      const banished = yield* photos.fromUrl(ownerId as never, PNG_URL);
      const fresh = yield* photos.fromUrl(ownerId as never, PNG_URL);

      yield* db.use((d) =>
        d.insert(schema.recipe).values({ ownerId, title: "Uses a photo", photoKey: used.id }),
      );
      yield* db.use((d) =>
        d.insert(schema.recipe).values({
          ownerId,
          title: "Banished",
          photoKey: banished.id,
          deletedAt: new Date(),
        }),
      );

      const staleUpload = yield* photos.startUpload(ownerId as never, {
        contentType: "image/png",
        size: 10,
      });
      const freshUpload = yield* photos.startUpload(ownerId as never, {
        contentType: "image/png",
        size: 10,
      });
      yield* storage.put(uploadKey(ownerId, staleUpload.id), new Uint8Array([1]), "image/png");
      yield* storage.put(uploadKey(ownerId, freshUpload.id), new Uint8Array([1]), "image/png");

      const old = new Date(Date.now() - 2 * DAY);
      yield* db.use((d) =>
        d
          .update(schema.photo)
          .set({ createdAt: old })
          .where(inArray(schema.photo.id, [orphan.id, used.id, banished.id])),
      );
      yield* db.use((d) =>
        d
          .update(schema.photoUpload)
          .set({ createdAt: old })
          .where(eq(schema.photoUpload.id, staleUpload.id)),
      );

      const removed = yield* photos.cleanup();
      assert.deepStrictEqual(removed, { uploads: 1, photos: 1 });

      const remaining = yield* db.use((d) => d.select({ id: schema.photo.id }).from(schema.photo));
      const ids = remaining.map((r) => r.id);
      assert.isFalse(ids.includes(orphan.id));
      for (const kept of [used, banished, fresh]) assert.isTrue(ids.includes(kept.id));

      const uploads = yield* db.use((d) =>
        d.select({ id: schema.photoUpload.id }).from(schema.photoUpload),
      );
      const uploadIds = uploads.map((r) => r.id);
      assert.isFalse(uploadIds.includes(staleUpload.id));
      assert.isTrue(uploadIds.includes(freshUpload.id));

      const stored = yield* keys();
      for (const v of ["thumb", "card", "full"] as const) {
        assert.isFalse(stored.includes(variantKey(ownerId, orphan.id, v)));
        for (const kept of [used, banished, fresh]) {
          assert.isTrue(stored.includes(variantKey(ownerId, kept.id, v)));
        }
      }
      assert.isFalse(stored.includes(uploadKey(ownerId, staleUpload.id)));
      assert.isTrue(stored.includes(uploadKey(ownerId, freshUpload.id)));
    }),
  );
});
