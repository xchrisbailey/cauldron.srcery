import { InvalidRequest, MAX_PAGE_LIMIT, PageQuery } from "@cauldron/shared";
import { timestampMs } from "@cauldron/db";
import { PGlite } from "@electric-sql/pglite";
import { desc } from "drizzle-orm";
import { drizzle } from "drizzle-orm/pglite";
import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { Effect, Schema } from "effect";
import { afterAll, beforeAll, describe, expect, it } from "vite-plus/test";
import { makeCursor, paginate } from "../src/Pagination.ts";

const items = pgTable("pagination_items", {
  id: text("id").primaryKey(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull(),
});

// Keyset columns default to now() here: Postgres stamps them itself, so
// precision 3 (timestampMs) is what keeps them comparable with a JS Date.
const stamped = pgTable("pagination_stamped", {
  id: uuid("id").primaryKey().defaultRandom(),
  createdAt: timestampMs("created_at").notNull().defaultNow(),
});

const Uuid = Schema.String.check(Schema.isUUID());

const client = new PGlite();
const db = drizzle({ client });

// 25 rows one second apart, plus a tie group of three rows sharing one instant.
const base = Date.parse("2026-01-01T00:00:00.000Z");
const rows = [
  ...Array.from({ length: 25 }, (_, n) => ({
    id: `r${String(n).padStart(2, "0")}`,
    createdAt: new Date(base + n * 1000),
  })),
  ...["tie-a", "tie-b", "tie-c"].map((id) => ({ id, createdAt: new Date(base + 10_000) })),
];
const expectedOrder = [...rows]
  .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime() || (a.id < b.id ? 1 : -1))
  .map((r) => r.id);

beforeAll(async () => {
  await client.exec(
    "create table pagination_items (id text primary key, created_at timestamptz not null)",
  );
  await db.insert(items).values(rows);
  await client.exec(
    "create table pagination_stamped (id uuid primary key default gen_random_uuid(), created_at timestamptz(3) not null default now())",
  );
  // One statement each, so every row gets its own now(); a few in the same millisecond.
  for (let n = 0; n < 40; n++) await db.insert(stamped).values({});
});
afterAll(() => client.close());

const page = (query: PageQuery) =>
  paginate({
    query,
    createdAt: items.createdAt,
    id: items.id,
    idSchema: Schema.String,
    run: ({ where, limit }) =>
      Effect.promise(() =>
        db
          .select()
          .from(items)
          .where(where)
          .orderBy(desc(items.createdAt), desc(items.id))
          .limit(limit),
      ),
  });

const walk = (limit: number) =>
  Effect.gen(function* () {
    const pages: Array<ReadonlyArray<string>> = [];
    let cursor: string | undefined;
    do {
      const result = yield* page({ limit, ...(cursor ? { cursor } : {}) });
      pages.push(result.items.map((r) => r.id));
      cursor = result.nextCursor ?? undefined;
    } while (cursor);
    return pages;
  });

describe("paginate", () => {
  it("returns the first page with a cursor, using the default limit of 20", async () => {
    const result = await Effect.runPromise(page({}));
    expect(result.items.map((r) => r.id)).toEqual(expectedOrder.slice(0, 20));
    expect(result.nextCursor).toEqual(expect.any(String));
  });

  it("follows cursors to the end and returns every row exactly once", async () => {
    const pages = await Effect.runPromise(walk(5));
    expect(pages.flat()).toEqual(expectedOrder);
    expect(pages.map((p) => p.length)).toEqual([5, 5, 5, 5, 5, 3]);
  });

  it("returns a null nextCursor on the last page, including an exact fit", async () => {
    const all = await Effect.runPromise(page({ limit: 28 }).pipe(Effect.map((r) => r)));
    expect(all.items).toHaveLength(28);
    expect(all.nextCursor).toBeNull();
    const pages = await Effect.runPromise(walk(14));
    expect(pages.map((p) => p.length)).toEqual([14, 14]);
  });

  it("breaks ties on createdAt by id, even when a page boundary splits the tie", async () => {
    for (const limit of [1, 2, 3, 4]) {
      const pages = await Effect.runPromise(walk(limit));
      const flat = pages.flat();
      expect(flat).toEqual(expectedOrder);
      expect(flat.filter((id) => id.startsWith("tie-"))).toEqual(["tie-c", "tie-b", "tie-a"]);
    }
  });

  it("fails an invalid cursor with InvalidRequest", async () => {
    const forged = Buffer.from(JSON.stringify({ c: "not a date", i: "x" })).toString("base64url");
    for (const cursor of ["!!!", "bm90IGpzb24", forged]) {
      const error = await Effect.runPromise(page({ cursor }).pipe(Effect.flip));
      expect(error).toBeInstanceOf(InvalidRequest);
    }
  });

  it("accepts a cursor it made itself", async () => {
    const cursor = await Effect.runPromise(
      makeCursor({ createdAt: new Date(base + 10_000), id: "tie-b" }),
    );
    const result = await Effect.runPromise(page({ cursor, limit: 2 }));
    expect(result.items.map((r) => r.id)).toEqual(["tie-a", "r10"]);
  });
});

describe("paginate with a uuid id and database-stamped timestamps", () => {
  const stampedPage = (query: PageQuery) =>
    paginate({
      query,
      createdAt: stamped.createdAt,
      id: stamped.id,
      idSchema: Uuid,
      run: ({ where, limit }) =>
        Effect.promise(() =>
          db
            .select()
            .from(stamped)
            .where(where)
            .orderBy(desc(stamped.createdAt), desc(stamped.id))
            .limit(limit),
        ),
    });

  it("walks every row exactly once in order, whatever the page size", async () => {
    const all = await db.select().from(stamped).orderBy(desc(stamped.createdAt), desc(stamped.id));
    for (const limit of [1, 3, 7]) {
      const ids: Array<string> = [];
      let cursor: string | undefined;
      do {
        const result = await Effect.runPromise(
          stampedPage({ limit, ...(cursor ? { cursor } : {}) }),
        );
        ids.push(...result.items.map((r) => r.id));
        cursor = result.nextCursor ?? undefined;
      } while (cursor);
      expect(ids).toEqual(all.map((r) => r.id));
    }
  });

  it("stores millisecond-precision timestamps, so a cursor round-trips exactly", async () => {
    const [row] = await db.select().from(stamped).limit(1);
    const raw = await client.query<{ us: string }>(
      "select (extract(epoch from created_at) * 1000000)::bigint::text as us from pagination_stamped limit 1",
    );
    expect(Number(raw.rows[0]!.us) % 1000).toBe(0);
    expect(row!.createdAt.getTime() * 1000).toBeGreaterThan(0);
  });

  it("rejects a cursor whose id is not a uuid as InvalidRequest, before touching the database", async () => {
    const forged = Buffer.from(
      JSON.stringify({ c: new Date(base).toISOString(), i: "not-a-uuid'; drop table x" }),
    ).toString("base64url");
    const error = await Effect.runPromise(stampedPage({ cursor: forged }).pipe(Effect.flip));
    expect(error).toBeInstanceOf(InvalidRequest);
  });
});

describe("PageQuery", () => {
  const decode = Schema.decodeUnknownSync(PageQuery);

  it("decodes limit from a string and allows both fields to be absent", () => {
    expect(decode({})).toEqual({});
    expect(decode({ limit: "50", cursor: "abc" })).toEqual({ limit: 50, cursor: "abc" });
  });

  it("enforces limit bounds", () => {
    expect(decode({ limit: "1" })).toEqual({ limit: 1 });
    expect(decode({ limit: String(MAX_PAGE_LIMIT) })).toEqual({ limit: MAX_PAGE_LIMIT });
    for (const limit of ["0", "-1", String(MAX_PAGE_LIMIT + 1), "2.5", "abc"]) {
      expect(() => decode({ limit })).toThrow();
    }
  });
});
