import { schema } from "@cauldron/db";
import { layer } from "@effect/vitest";
import { eq } from "drizzle-orm";
import { Duration, Effect, Layer } from "effect";
import { TestClock } from "effect/testing";
import { expect } from "vite-plus/test";
import { Db } from "../src/Db.ts";
import { ImportQueue, INPUT_RETENTION, JOB_RETENTION } from "../src/imports/ImportQueue.ts";
import { makeOwner, TestServices } from "./helpers.ts";

// The retention job, on the test clock. Rows are inserted with explicit
// created_at values counted back from the clock's now.

const Services = ImportQueue.layer.pipe(Layer.provideMerge(TestServices()));

const NOON = Date.parse("2026-10-01T12:00:00Z");
const DAY = Duration.toMillis(Duration.days(1));
const DRAFT = { title: "Dal", ingredients: [], steps: [] };

const insertJob = Effect.fn("insertJob")(function* (
  ageDays: number,
  status: (typeof schema.importJob.$inferInsert)["status"],
  text: boolean = true,
) {
  const db = yield* Db;
  const ownerId = yield* makeOwner();
  const createdAt = new Date(NOON - ageDays * DAY);
  const [row] = yield* db.use((d) =>
    d
      .insert(schema.importJob)
      .values({
        ownerId,
        status,
        source: text ? "text" : "web",
        sourceUrl: text ? null : "https://example.com/dal",
        inputText: text ? "pasted dal" : null,
        rawContent: "read dal",
        draft: DRAFT,
        createdAt,
        updatedAt: createdAt,
      })
      .returning(),
  );
  return row!;
});

const find = Effect.fn("find")(function* (id: string) {
  const db = yield* Db;
  const [row] = yield* db.use((d) =>
    d.select().from(schema.importJob).where(eq(schema.importJob.id, id)),
  );
  return row;
});

layer(Services)("import cleanup", (it) => {
  it.effect("names the retention periods", () =>
    Effect.sync(() => {
      expect(Duration.toMillis(INPUT_RETENTION)).toBe(7 * DAY);
      expect(Duration.toMillis(JOB_RETENTION)).toBe(30 * DAY);
    }),
  );

  it.effect("deletes jobs past 30 days", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const old = yield* insertJob(31, "done");
      const result = yield* queue.cleanup();
      expect(result.deleted).toBeGreaterThanOrEqual(1);
      expect(yield* find(old.id)).toBeUndefined();
    }),
  );

  it.effect("strips the text of an 8-day-old finished job, keeping the rest", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const pasted = yield* insertJob(8, "done");
      const linked = yield* insertJob(8, "failed", false);
      yield* queue.cleanup();
      expect(yield* find(pasted.id)).toMatchObject({
        status: "done",
        inputText: null,
        rawContent: null,
        draft: DRAFT,
        source: "text",
      });
      expect(yield* find(linked.id)).toMatchObject({
        status: "failed",
        sourceUrl: "https://example.com/dal",
        rawContent: null,
      });
    }),
  );

  it.effect("leaves a 6-day-old job alone", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const recent = yield* insertJob(6, "done");
      yield* queue.cleanup();
      expect(yield* find(recent.id)).toMatchObject({
        inputText: "pasted dal",
        rawContent: "read dal",
      });
    }),
  );

  it.effect("does not strip an old job that is still queued or running", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const queued = yield* insertJob(8, "queued");
      const running = yield* insertJob(8, "running");
      yield* queue.cleanup();
      for (const { id } of [queued, running]) {
        expect(yield* find(id)).toMatchObject({ inputText: "pasted dal", rawContent: "read dal" });
      }
      // Mark them ended so they don't sit in the shared queue.
      const db = yield* Db;
      yield* db.use((d) =>
        d
          .update(schema.importJob)
          .set({ status: "cancelled" })
          .where(eq(schema.importJob.id, queued.id)),
      );
      yield* db.use((d) =>
        d
          .update(schema.importJob)
          .set({ status: "cancelled" })
          .where(eq(schema.importJob.id, running.id)),
      );
    }),
  );

  it.effect("follows the test clock", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const job = yield* insertJob(6, "done");
      yield* queue.cleanup();
      expect((yield* find(job.id))?.inputText).toBe("pasted dal");
      yield* TestClock.adjust("2 days");
      yield* queue.cleanup();
      expect((yield* find(job.id))?.inputText).toBeNull();
      yield* TestClock.adjust("23 days");
      yield* queue.cleanup();
      expect(yield* find(job.id)).toBeUndefined();
    }),
  );
});
