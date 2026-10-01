import { schema } from "@cauldron/db";
import { copy, ImportId, type ImportInput } from "@cauldron/shared";
import { layer } from "@effect/vitest";
import { eq } from "drizzle-orm";
import { Duration, Effect, Layer } from "effect";
import { TestClock } from "effect/testing";
import { expect } from "vite-plus/test";
import { Db } from "../src/Db.ts";
import { DAILY_IMPORT_LIMIT, Imports } from "../src/Imports.ts";
import { ImportQueue, MAX_ATTEMPTS, STALE_AFTER } from "../src/imports/ImportQueue.ts";
import { makeOwner, TestServices } from "./helpers.ts";

// The job queue and the daily limit, on the test clock. No worker runs here:
// each test claims and finishes its own jobs, and leaves none queued or
// running for the next.

const Services = Layer.mergeAll(ImportQueue.layer, Imports.layer).pipe(
  Layer.provideMerge(TestServices()),
);

const NOON = Date.parse("2026-10-01T12:00:00Z");
const PASTE: ImportInput = { text: "dal" };
const job = { source: "text", url: null, text: "dal" } as const;
// Any end will do, to clear a job out of the next test's way.
const ended = { _tag: "Failed", code: "noRecipe" } as const;

const row = Effect.fn("row")(function* (id: string) {
  const db = yield* Db;
  const [found] = yield* db.use((d) =>
    d.select().from(schema.importJob).where(eq(schema.importJob.id, id)),
  );
  return found!;
});

layer(Services)("the import queue", (it) => {
  it.effect("hands out the oldest queued job, to one worker", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const owner = yield* makeOwner();
      const first = yield* queue.enqueue(owner, job);
      yield* TestClock.adjust("1 second");
      const second = yield* queue.enqueue(owner, job);
      expect(first).toMatchObject({ status: "queued", attempts: 0 });
      expect(first.createdAt).toEqual(new Date(NOON));

      const claimed = yield* queue.claim();
      expect(claimed).toMatchObject({ id: first.id, status: "running", attempts: 1 });
      expect(claimed?.startedAt).toEqual(new Date(NOON + 1000));
      expect((yield* queue.claim())?.id).toBe(second.id);
      expect(yield* queue.claim()).toBeUndefined();
      for (const { id } of [first, second]) yield* queue.finish(id, ended);
    }),
  );

  it.effect("puts back a job a stopping worker had, without counting the attempt", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const queued = yield* queue.enqueue(yield* makeOwner(), job);
      yield* queue.claim();
      yield* queue.requeue(queued.id);
      expect(yield* queue.claim()).toMatchObject({ id: queued.id, attempts: 1 });
      expect(yield* queue.claim()).toBeUndefined();
      yield* queue.finish(queued.id, ended);
    }),
  );

  it.effect("requeues a job a stopped worker left running, once it's stale", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const queued = yield* queue.enqueue(yield* makeOwner(), job);
      yield* queue.claim();
      // Still within its time: it may yet finish.
      yield* TestClock.adjust(Duration.subtract(STALE_AFTER, Duration.seconds(1)));
      yield* queue.recover();
      expect(yield* queue.claim()).toBeUndefined();
      yield* TestClock.adjust("2 seconds");
      yield* queue.recover();
      const again = yield* queue.claim();
      expect(again).toMatchObject({ id: queued.id, attempts: 2, errorCode: null });
      yield* queue.finish(queued.id, ended);
    }),
  );

  it.effect("gives up on a job after three tries", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const imports = yield* Imports;
      const owner = yield* makeOwner();
      const queued = yield* queue.enqueue(owner, job);
      for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
        expect(yield* queue.claim()).toMatchObject({ id: queued.id, attempts: attempt });
        yield* TestClock.adjust(Duration.sum(STALE_AFTER, Duration.seconds(1)));
        yield* queue.recover();
      }
      expect(yield* queue.claim()).toBeUndefined();
      const gaveUp = yield* imports.get(owner, ImportId.make(queued.id));
      expect(gaveUp).toMatchObject({
        status: "failed",
        failure: { code: "unavailable", message: copy.imports.unavailable.text },
      });
    }),
  );

  it.effect("records how a job ended, with its cost and what it read", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const owner = yield* makeOwner();

      const done = yield* queue.enqueue(owner, job);
      yield* queue.claim();
      yield* TestClock.adjust("3 seconds");
      const draft = {
        title: "Dal",
        description: null,
        servings: null,
        prepMinutes: null,
        cookMinutes: null,
        totalMinutes: null,
        sourcePlatform: "text" as const,
        sourceUrl: null,
        sourceAuthor: null,
        siteName: null,
        notes: null,
        photoKey: null,
        tags: [],
        ingredients: [],
        steps: [],
        unsure: [],
      };
      yield* queue.finish(done.id, {
        _tag: "Done",
        distilled: {
          draft,
          extractor: "model",
          raw: "dal",
          usage: { model: "fake", inputTokens: 3, outputTokens: 100 },
        },
      });
      expect(yield* row(done.id)).toMatchObject({
        status: "done",
        draft,
        extractor: "model",
        rawContent: "dal",
        model: "fake",
        inputTokens: 3,
        outputTokens: 100,
        finishedAt: new Date(NOON + 3000),
      });

      // Kept for #17, which will transcribe posts whose recipe is spoken.
      const failed = yield* queue.enqueue(owner, job);
      yield* queue.claim();
      yield* queue.finish(failed.id, { _tag: "Failed", code: "spokenOnly", raw: "in the video" });
      expect(yield* row(failed.id)).toMatchObject({
        status: "failed",
        errorCode: "spokenOnly",
        rawContent: "in the video",
      });
    }),
  );

  it.effect("leaves a job cancelled while it ran as cancelled", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const queue = yield* ImportQueue;
      const owner = yield* makeOwner();
      const queued = yield* queue.enqueue(owner, job);
      yield* queue.claim();
      expect(yield* queue.cancelled(queued.id)).toBe(false);
      // Someone else's cancel doesn't touch it.
      expect(yield* queue.cancel(yield* makeOwner(), queued.id)).toBeUndefined();
      expect(yield* queue.cancel(owner, queued.id)).toMatchObject({ status: "cancelled" });
      expect(yield* queue.cancelled(queued.id)).toBe(true);
      yield* queue.finish(queued.id, { _tag: "Failed", code: "noRecipe" });
      expect(yield* row(queued.id)).toMatchObject({ status: "cancelled", errorCode: null });
      // Nor is a finished job cancelled.
      expect(yield* queue.cancel(owner, queued.id)).toBeUndefined();
    }),
  );
});

layer(Services)("the daily limit", (it) => {
  it.effect("caps imports per person per day", () =>
    Effect.gen(function* () {
      yield* TestClock.setTime(NOON);
      const imports = yield* Imports;
      const ada = yield* makeOwner();
      yield* Effect.forEach(
        Array.from({ length: DAILY_IMPORT_LIMIT }),
        () => imports.start(ada, PASTE),
        { discard: true },
      );
      const refused = yield* Effect.flip(imports.start(ada, PASTE));
      expect(refused).toMatchObject({
        _tag: "TooManyRequests",
        message: copy.imports.dailyLimit.text,
      });
      // Someone else still can.
      expect(yield* imports.start(yield* makeOwner(), PASTE)).toMatchObject({ status: "queued" });
      // A day after the first, there's room again.
      yield* TestClock.adjust(Duration.subtract(Duration.days(1), Duration.seconds(1)));
      expect((yield* Effect.flip(imports.start(ada, PASTE)))._tag).toBe("TooManyRequests");
      yield* TestClock.adjust("1 second");
      expect(yield* imports.start(ada, PASTE)).toMatchObject({ status: "queued" });
    }),
  );
});
