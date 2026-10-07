import { schema } from "@cauldron/db";
import type { ImportFailureCode, ImportSource, UserId } from "@cauldron/shared";
import { and, count, eq, gt, inArray, isNotNull, lt, notInArray, or, sql } from "drizzle-orm";
import { Context, DateTime, Duration, Effect, Layer } from "effect";
import { Db } from "../Db.ts";
import type { Distilled } from "./distill.ts";

// The import_job table as a queue. Every time it writes or compares comes
// from Effect's Clock, so tests move time with TestClock. Internal to
// Imports: nothing here checks who is asking.

const { importJob } = schema;
export type JobRow = typeof importJob.$inferSelect;

/** Jobs left running this long were orphaned by a stopped worker and are picked up again. */
export const STALE_AFTER = Duration.minutes(5);
export const MAX_ATTEMPTS = 3;
/** Pasted text and what was read from a page are dropped from finished jobs after this long. */
export const INPUT_RETENTION = Duration.days(7);
/** Jobs are deleted after this long. The daily cap only looks back a day. */
export const JOB_RETENTION = Duration.days(30);

/** How a job ended: a draft, or a plain reason with what was read before it failed. */
export type Outcome =
  | { readonly _tag: "Done"; readonly distilled: Distilled }
  | {
      readonly _tag: "Failed";
      readonly code: ImportFailureCode;
      readonly raw?: string | undefined;
    };

const make = Effect.gen(function* () {
  const db = yield* Db;
  const now = DateTime.nowAsDate;

  /** Queues a link or pasted text for the owner. */
  const enqueue = Effect.fn("ImportQueue.enqueue")(function* (
    ownerId: UserId,
    job: {
      readonly source: ImportSource;
      readonly url: string | null;
      readonly text: string | null;
    },
  ) {
    const createdAt = yield* now;
    const [row] = yield* db.use((d) =>
      d
        .insert(importJob)
        .values({
          ownerId,
          source: job.source,
          sourceUrl: job.url,
          inputText: job.text,
          createdAt,
          updatedAt: createdAt,
        })
        .returning(),
    );
    return row!;
  });

  /** Takes the oldest queued job, so no other worker can. */
  const claim = Effect.fn("ImportQueue.claim")(function* () {
    const startedAt = yield* now;
    const [row] = yield* db.use((d) =>
      d
        .update(importJob)
        .set({ status: "running", attempts: sql`${importJob.attempts} + 1`, startedAt })
        .where(
          eq(
            importJob.id,
            sql`(select ${importJob.id} from ${importJob} where ${importJob.status} = 'queued' order by ${importJob.createdAt} limit 1 for update skip locked)`,
          ),
        )
        .returning(),
    );
    return row;
  });

  /** Records how a running job ended, unless it was cancelled meanwhile. */
  const finish = Effect.fn("ImportQueue.finish")(function* (id: string, outcome: Outcome) {
    const finishedAt = yield* now;
    const values: Partial<typeof importJob.$inferInsert> =
      outcome._tag === "Done"
        ? {
            status: "done",
            draft: outcome.distilled.draft,
            extractor: outcome.distilled.extractor,
            rawContent: outcome.distilled.raw,
            model: outcome.distilled.usage?.model ?? null,
            inputTokens: outcome.distilled.usage?.inputTokens ?? null,
            outputTokens: outcome.distilled.usage?.outputTokens ?? null,
          }
        : { status: "failed", errorCode: outcome.code, rawContent: outcome.raw ?? null };
    yield* db.use((d) =>
      d
        .update(importJob)
        .set({ ...values, finishedAt })
        .where(and(eq(importJob.id, id), eq(importJob.status, "running"))),
    );
  });

  /** Puts a job a stopping worker was running back in the queue, without counting the attempt. */
  const requeue = Effect.fn("ImportQueue.requeue")(function* (id: string) {
    yield* db.use((d) =>
      d
        .update(importJob)
        .set({ status: "queued", attempts: sql`greatest(${importJob.attempts} - 1, 0)` })
        .where(and(eq(importJob.id, id), eq(importJob.status, "running"))),
    );
  });

  /** Cancels the owner's job if it hasn't finished. Returns the row it changed, if any. */
  const cancel = Effect.fn("ImportQueue.cancel")(function* (ownerId: UserId, id: string) {
    const finishedAt = yield* now;
    const [row] = yield* db.use((d) =>
      d
        .update(importJob)
        .set({ status: "cancelled", finishedAt })
        .where(
          and(
            eq(importJob.id, id),
            eq(importJob.ownerId, ownerId),
            inArray(importJob.status, ["queued", "running"]),
          ),
        )
        .returning(),
    );
    return row;
  });

  /** Whether a job was cancelled, perhaps before its fiber could be interrupted. */
  const cancelled = Effect.fn("ImportQueue.cancelled")(function* (id: string) {
    const [row] = yield* db.use((d) =>
      d.select({ status: importJob.status }).from(importJob).where(eq(importJob.id, id)),
    );
    return row?.status === "cancelled";
  });

  /** Requeues jobs a stopped worker left running, and gives up on ones that keep failing. */
  const recover = Effect.fn("ImportQueue.recover")(function* () {
    const at = yield* now;
    const before = new Date(at.getTime() - Duration.toMillis(STALE_AFTER));
    const stale = and(eq(importJob.status, "running"), lt(importJob.startedAt, before));
    yield* db.use((d) =>
      d
        .update(importJob)
        .set({ status: "failed", errorCode: "unavailable", finishedAt: at })
        .where(and(stale, sql`${importJob.attempts} >= ${MAX_ATTEMPTS}`)),
    );
    yield* db.use((d) =>
      d
        .update(importJob)
        .set({ status: "queued" })
        .where(and(stale, lt(importJob.attempts, MAX_ATTEMPTS))),
    );
  });

  /** How many jobs the owner queued in the window up to now. */
  const countSince = Effect.fn("ImportQueue.countSince")(function* (
    ownerId: UserId,
    window: Duration.Input,
  ) {
    const at = yield* now;
    const since = new Date(at.getTime() - Duration.toMillis(window));
    const [row] = yield* db.use((d) =>
      d
        .select({ n: count() })
        .from(importJob)
        .where(and(eq(importJob.ownerId, ownerId), gt(importJob.createdAt, since))),
    );
    return Number(row?.n ?? 0);
  });

  /**
   * Drops the text of finished jobs after INPUT_RETENTION (the draft, link and
   * status stay) and deletes jobs after JOB_RETENTION. A job still queued or
   * running keeps its text, since a worker needs it.
   */
  const cleanup = Effect.fn("ImportQueue.cleanup")(function* () {
    const at = yield* now;
    const ago = (age: Duration.Input) => new Date(at.getTime() - Duration.toMillis(age));
    const deleted = yield* db.use((d) =>
      d
        .delete(importJob)
        .where(lt(importJob.createdAt, ago(JOB_RETENTION)))
        .returning({ id: importJob.id }),
    );
    const stripped = yield* db.use((d) =>
      d
        .update(importJob)
        .set({ inputText: null, rawContent: null })
        .where(
          and(
            lt(importJob.createdAt, ago(INPUT_RETENTION)),
            notInArray(importJob.status, ["queued", "running"]),
            or(isNotNull(importJob.inputText), isNotNull(importJob.rawContent)),
          ),
        )
        .returning({ id: importJob.id }),
    );
    return { stripped: stripped.length, deleted: deleted.length };
  });

  return { enqueue, claim, finish, requeue, cancel, cancelled, recover, countSince, cleanup };
});

/** The import_job table as a work queue, for Imports and its worker. */
export class ImportQueue extends Context.Service<ImportQueue, Effect.Success<typeof make>>()(
  "cauldron/api/ImportQueue",
) {
  static readonly layer = Layer.effect(ImportQueue, make);
}
