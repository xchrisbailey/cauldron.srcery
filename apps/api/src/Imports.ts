import { schema } from "@cauldron/db";
import {
  Conflict,
  copy,
  ImportDraft,
  type ImportFailureCode,
  ImportId,
  type ImportInput,
  ImportJob,
  type ImportSource,
  NotFound,
  RecipeId,
  type RecipeInput,
  TooManyRequests,
  type UserId,
} from "@cauldron/shared";
import { and, desc, eq, inArray, sql } from "drizzle-orm";
import {
  Cause,
  Context,
  Duration,
  Effect,
  Exit,
  Fiber,
  FiberMap,
  Layer,
  Option,
  Queue,
  Schedule,
  Schema,
} from "effect";
import type { AppConfig } from "./AppConfig.ts";
import { Db } from "./Db.ts";
import { classify, distill, normalizeUrl } from "./imports/distill.ts";
import { ImportQueue, type JobRow } from "./imports/ImportQueue.ts";
import type { RecipeExtractor } from "./imports/RecipeExtractor.ts";
import { Photos } from "./Photos.ts";
import { liveRecipe, Recipes } from "./Recipes.ts";
import type { RemoteFetch } from "./RemoteFetch.ts";

const { importJob, recipe } = schema;

/** Imports one person can start in a day. Each may call the model, which costs money. */
export const DAILY_IMPORT_LIMIT = 100;
/** Jobs run at once per API process. */
const CONCURRENCY = 2;
const POLL = Duration.seconds(2);

const notFound = () => new NotFound({ message: copy.errors.notFound.text });

const failureMessage = (code: ImportFailureCode, source: ImportSource) =>
  code === "noRecipe" && source === "text"
    ? copy.imports.noRecipeInText.text
    : copy.imports[code].text;

const decodeDraft = Schema.decodeUnknownOption(ImportDraft);

const make = Effect.gen(function* () {
  const db = yield* Db;
  const recipes = yield* Recipes;
  const photos = yield* Photos;
  const queue = yield* ImportQueue;
  // What distill reads through: the network, the model, photo storage and config.
  const seams = yield* Effect.context<RemoteFetch | RecipeExtractor | Photos | AppConfig>();
  // Wakes an idle worker when a job is queued, so it doesn't wait for the next poll.
  const wake = yield* Queue.unbounded<void>();
  // Running jobs by id, so cancelling one interrupts its work.
  const running = yield* FiberMap.make<string>();

  const findRow = Effect.fn("Imports.findRow")(function* (ownerId: UserId, id: ImportId) {
    const [row] = yield* db.use((d) =>
      d
        .select()
        .from(importJob)
        .where(and(eq(importJob.id, id), eq(importJob.ownerId, ownerId))),
    );
    if (!row) return yield* notFound();
    return row;
  });

  /** A live recipe already in the box from the same link. */
  const duplicateOf = Effect.fn("Imports.duplicateOf")(function* (
    row: JobRow,
    draft: ImportDraft | null,
  ) {
    const links = [row.sourceUrl, draft?.sourceUrl ?? null].filter((l): l is string => l !== null);
    if (links.length === 0) return null;
    const candidates = [...new Set(links.flatMap((link) => [link, normalizeUrl(link)]))];
    const [match] = yield* db.use((d) =>
      d
        .select({ id: recipe.id, title: recipe.title })
        .from(recipe)
        .where(
          and(
            liveRecipe(row.ownerId),
            inArray(recipe.sourceUrl, candidates),
            // The recipe this job saved isn't a duplicate of itself.
            row.recipeId === null ? undefined : sql`${recipe.id} <> ${row.recipeId}`,
          ),
        )
        .orderBy(desc(recipe.createdAt))
        .limit(1),
    );
    return match ? { id: RecipeId.make(match.id), title: match.title } : null;
  });

  const toJob = Effect.fn("Imports.toJob")(function* (row: JobRow) {
    const draft =
      row.status === "done" || row.status === "saved"
        ? Option.getOrNull(decodeDraft(row.draft))
        : null;
    const code = row.errorCode as ImportFailureCode | null;
    return new ImportJob({
      id: ImportId.make(row.id),
      status: row.status,
      source: row.source as ImportSource,
      sourceUrl: row.sourceUrl,
      draft,
      failure:
        row.status === "failed" && code !== null
          ? { code, message: failureMessage(code, row.source as ImportSource) }
          : null,
      duplicateOf: yield* duplicateOf(row, draft),
      recipeId: row.recipeId === null ? null : RecipeId.make(row.recipeId),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    });
  });

  const start = Effect.fn("Imports.start")(function* (ownerId: UserId, input: ImportInput) {
    if ((yield* queue.countSince(ownerId, Duration.days(1))) >= DAILY_IMPORT_LIMIT) {
      return yield* new TooManyRequests({
        message: copy.imports.dailyLimit.text,
        retryAfterSeconds: 60 * 60,
      });
    }
    const url = input.url === undefined ? null : input.url;
    const row = yield* queue.enqueue(ownerId, {
      source: url === null ? "text" : classify(url),
      url,
      text: input.text ?? null,
    });
    yield* Queue.offer(wake, undefined);
    return yield* toJob(row);
  });

  const get = Effect.fn("Imports.get")(function* (ownerId: UserId, id: ImportId) {
    return yield* toJob(yield* findRow(ownerId, id));
  });

  const cancel = Effect.fn("Imports.cancel")(function* (ownerId: UserId, id: ImportId) {
    const row = yield* queue.cancel(ownerId, id);
    // Interrupts the job if this process is running it. Another process's
    // worker sees the status when it finishes and leaves the row alone.
    yield* FiberMap.remove(running, id);
    return yield* toJob(row ?? (yield* findRow(ownerId, id)));
  });

  /** Saves the reviewed draft as a recipe. A draft is saved once. */
  const save = Effect.fn("Imports.save")(function* (
    ownerId: UserId,
    id: ImportId,
    input: RecipeInput,
  ) {
    const row = yield* findRow(ownerId, id);
    if (row.status !== "done") {
      return yield* new Conflict({
        message:
          row.status === "saved" ? copy.imports.alreadySaved.text : copy.imports.notReady.text,
      });
    }
    // Where it came from is the job's to say, not the client's.
    const draft = Option.getOrNull(decodeDraft(row.draft));
    const link = input.sourceUrl ?? draft?.sourceUrl ?? row.sourceUrl;
    // A draft's photo is cleaned up if it waits a day unsaved; save without it then.
    const photoKey =
      input.photoKey !== null && !(yield* photos.owns(ownerId, input.photoKey))
        ? null
        : input.photoKey;
    const sourced: RecipeInput = {
      ...input,
      photoKey,
      sourcePlatform: row.source as ImportSource,
      sourceUrl: link === null ? null : normalizeUrl(link),
    };
    return yield* db.transaction(
      Effect.gen(function* () {
        const created = yield* recipes.create(ownerId, sourced);
        const claimed = yield* db.use((d) =>
          d
            .update(importJob)
            .set({ status: "saved", recipeId: created.id })
            .where(and(eq(importJob.id, id), eq(importJob.status, "done")))
            .returning({ id: importJob.id }),
        );
        // Saved twice at once: the second save rolls back.
        if (claimed.length === 0) {
          return yield* new Conflict({ message: copy.imports.alreadySaved.text });
        }
        return created;
      }),
    );
  });

  const work = Effect.fn("Imports.work")(function* (row: JobRow) {
    // A cancel that landed between the claim and now: don't spend a model call.
    if (yield* queue.cancelled(row.id)) return yield* Effect.interrupt;
    // A job has a link or text, never both (the table checks). Jobs whose text
    // was dropped (see ImportQueue.cleanup) are finished, so none reaches here.
    const request = row.inputText === null ? { url: row.sourceUrl! } : { text: row.inputText };
    return yield* distill(request, row.ownerId as UserId).pipe(Effect.provideContext(seams));
  });

  /** Runs one claimed job to a result, recording failures as plain codes. */
  const process = Effect.fn("Imports.process")(
    function* (row: JobRow) {
      // Interrupted by a cancel, the row is already cancelled and stays so. By a
      // shutdown, it goes back in the queue for the next worker.
      const fiber = yield* FiberMap.run(
        running,
        row.id,
        work(row).pipe(Effect.onInterrupt(() => queue.requeue(row.id).pipe(Effect.ignore))),
      );
      const exit = yield* Fiber.await(fiber);
      if (Exit.isSuccess(exit)) {
        return yield* queue.finish(row.id, { _tag: "Done", distilled: exit.value });
      }
      const cause = exit.cause;
      // Cancelled: the row already says so.
      if (Cause.hasInterrupts(cause)) return;
      const failure = Cause.findErrorOption(cause);
      // A DbError here is an outage, not a reason to show the cook.
      if (Option.isSome(failure) && failure.value._tag === "ImportFailed") {
        return yield* queue.finish(row.id, {
          _tag: "Failed",
          code: failure.value.code,
          raw: failure.value.raw,
        });
      }
      yield* Effect.logError("Import failed unexpectedly", cause);
      yield* queue.finish(row.id, { _tag: "Failed", code: "unavailable" });
    },
    (effect, row) => Effect.annotateLogs(effect, { importId: row.id }),
  );

  /** One worker: claim, run, repeat; idle until woken or the next poll. */
  const worker = Effect.gen(function* () {
    const row = yield* queue.claim();
    if (row) return yield* process(row);
    yield* Queue.take(wake).pipe(
      Effect.timeoutOrElse({ duration: POLL, orElse: () => Effect.void }),
    );
  }).pipe(
    Effect.catchCause((cause) =>
      Effect.logWarning("Import worker step failed", cause).pipe(
        Effect.andThen(Effect.sleep(POLL)),
      ),
    ),
    Effect.forever,
  );

  return { start, get, cancel, save, recover: queue.recover, cleanup: queue.cleanup, worker };
});

/** Distill jobs: start, poll, cancel and save. Every read and write is scoped to one owner. */
export class Imports extends Context.Service<Imports, Effect.Success<typeof make>>()(
  "cauldron/api/Imports",
) {
  static readonly layer = Layer.effect(Imports, make).pipe(
    Layer.provide([Recipes.layer, Photos.layer, ImportQueue.layer]),
  );
}

/** Runs the import workers in the background for as long as the API is up. */
export const ImportWorker = Layer.effectDiscard(
  Effect.gen(function* () {
    const imports = yield* Imports;
    yield* imports.recover().pipe(
      Effect.catchCause((cause) => Effect.logWarning("Import recovery failed", cause)),
      Effect.repeat(Schedule.spaced("1 minute")),
      Effect.forkScoped,
    );
    for (let i = 0; i < CONCURRENCY; i++) yield* Effect.forkScoped(imports.worker);
  }),
).pipe(Layer.provide(Imports.layer));

/** Drops old import text and deletes old jobs once a day in the background for as long as the API is up. */
export const ImportCleanup = Layer.effectDiscard(
  Effect.gen(function* () {
    const imports = yield* Imports;
    yield* imports.cleanup().pipe(
      Effect.tap((removed) =>
        removed.stripped + removed.deleted > 0
          ? Effect.logInfo("Cleaned up imports", removed)
          : Effect.void,
      ),
      Effect.catchCause((cause) => Effect.logWarning("Import cleanup failed", cause)),
      Effect.repeat(Schedule.spaced("1 day")),
      Effect.forkScoped,
    );
  }),
).pipe(Layer.provide(Imports.layer));
