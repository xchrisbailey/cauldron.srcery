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
  RECIPE_LIMITS,
  RecipeId,
  type RecipeInput,
  TooManyRequests,
  type UserId,
} from "@cauldron/shared";
import { and, count, desc, eq, gt, inArray, isNull, lt, sql } from "drizzle-orm";
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
import { Db } from "./Db.ts";
import { toDraft } from "./imports/draft.ts";
import type { ExtractedRecipe } from "./imports/Extracted.ts";
import { ImportFailed, Importers } from "./imports/Importers.ts";
import { RecipeExtractor } from "./imports/RecipeExtractor.ts";
import { Photos } from "./Photos.ts";
import { Recipes } from "./Recipes.ts";

const { importJob, recipe } = schema;
type JobRow = typeof importJob.$inferSelect;

/** Imports one person can start in a day. Each may call the model, which costs money. */
export const DAILY_IMPORT_LIMIT = 100;
/** A job that runs longer than this fails as timed out. */
export const JOB_TIMEOUT = Duration.minutes(2);
/** The cover photo gets this long; past it the draft goes without one. */
const PHOTO_TIMEOUT = Duration.seconds(20);
/** An estimate is a nicety: the draft goes out without one rather than waiting long. */
const MACRO_TIMEOUT = Duration.seconds(30);
/** Jobs left running this long were orphaned by a stopped worker and are picked up again. */
const STALE_AFTER = Duration.minutes(5);
const MAX_ATTEMPTS = 3;
/** Jobs run at once per API process. */
const CONCURRENCY = 2;
const POLL = Duration.seconds(2);

const notFound = () => new NotFound({ message: copy.errors.notFound.text });

const failureMessage = (code: ImportFailureCode, source: ImportSource) =>
  code === "noRecipe" && source === "text"
    ? copy.imports.noRecipeInText.text
    : copy.imports[code].text;

const TRACKING = /^(?:utm_.*|fbclid|gclid|igshid|igsh|mc_cid|mc_eid|ref|ref_src|si|s)$/i;

/**
 * A link without the parts that don't change the page (fragment, tracking
 * parameters, a trailing slash, the host's case), so the same recipe is
 * recognised however it was shared.
 */
export const normalizeUrl = (raw: string): string => {
  try {
    const url = new URL(raw);
    url.hash = "";
    // Copied first: deleting while iterating skips keys.
    for (const key of Array.from(url.searchParams.keys())) {
      if (TRACKING.test(key)) url.searchParams.delete(key);
    }
    if (url.pathname.length > 1) url.pathname = url.pathname.replace(/\/+$/, "");
    return url.toString();
  } catch {
    return raw;
  }
};

const SOCIAL: ReadonlyArray<readonly [RegExp, ImportSource]> = [
  [/(^|\.)instagram\.com$|(^|\.)instagr\.am$/i, "instagram"],
  [/(^|\.)tiktok\.com$/i, "tiktok"],
];

/** What kind of source a link is, from its host. */
export const detectSource = (url: string): ImportSource => {
  try {
    const host = new URL(url).hostname;
    return SOCIAL.find(([pattern]) => pattern.test(host))?.[1] ?? "web";
  } catch {
    return "web";
  }
};

const decodeDraft = Schema.decodeUnknownOption(ImportDraft);

const make = Effect.gen(function* () {
  const db = yield* Db;
  const recipes = yield* Recipes;
  const importers = yield* Importers;
  const photos = yield* Photos;
  const model = yield* RecipeExtractor;
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
            eq(recipe.ownerId, row.ownerId),
            isNull(recipe.deletedAt),
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
    const since = new Date(Date.now() - Duration.toMillis(Duration.days(1)));
    const [today] = yield* db.use((d) =>
      d
        .select({ n: count() })
        .from(importJob)
        .where(and(eq(importJob.ownerId, ownerId), gt(importJob.createdAt, since))),
    );
    if (Number(today?.n ?? 0) >= DAILY_IMPORT_LIMIT) {
      return yield* new TooManyRequests({
        message: copy.imports.dailyLimit.text,
        retryAfterSeconds: 60 * 60,
      });
    }
    const url = input.url === undefined ? null : input.url;
    const [row] = yield* db.use((d) =>
      d
        .insert(importJob)
        .values({
          ownerId,
          source: url === null ? "text" : detectSource(url),
          sourceUrl: url,
          inputText: input.text ?? null,
        })
        .returning(),
    );
    yield* Queue.offer(wake, undefined);
    return yield* toJob(row!);
  });

  const get = Effect.fn("Imports.get")(function* (ownerId: UserId, id: ImportId) {
    return yield* toJob(yield* findRow(ownerId, id));
  });

  const cancel = Effect.fn("Imports.cancel")(function* (ownerId: UserId, id: ImportId) {
    const [row] = yield* db.use((d) =>
      d
        .update(importJob)
        .set({ status: "cancelled", finishedAt: new Date() })
        .where(
          and(
            eq(importJob.id, id),
            eq(importJob.ownerId, ownerId),
            inArray(importJob.status, ["queued", "running"]),
          ),
        )
        .returning(),
    );
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

  /** Takes the oldest queued job, so no other worker can. */
  const claim = db
    .use((d) =>
      d
        .update(importJob)
        .set({
          status: "running",
          attempts: sql`${importJob.attempts} + 1`,
          startedAt: new Date(),
        })
        .where(
          eq(
            importJob.id,
            sql`(select ${importJob.id} from ${importJob} where ${importJob.status} = 'queued' order by ${importJob.createdAt} limit 1 for update skip locked)`,
          ),
        )
        .returning(),
    )
    .pipe(Effect.map((rows) => rows[0]));

  /** Writes a finished job, unless it was cancelled meanwhile. */
  const finish = (id: string, values: Partial<typeof importJob.$inferInsert>) =>
    db.use((d) =>
      d
        .update(importJob)
        .set({ ...values, finishedAt: new Date() })
        .where(and(eq(importJob.id, id), eq(importJob.status, "running"))),
    );

  /** Whether a job was cancelled, perhaps before its fiber could be interrupted. */
  const cancelled = (id: string) =>
    db
      .use((d) =>
        d.select({ status: importJob.status }).from(importJob).where(eq(importJob.id, id)),
      )
      .pipe(Effect.map((rows) => rows[0]?.status === "cancelled"));

  /** Puts a job a stopping worker was running back in the queue, without counting the attempt. */
  const requeue = (id: string) =>
    db
      .use((d) =>
        d
          .update(importJob)
          .set({ status: "queued", attempts: sql`greatest(${importJob.attempts} - 1, 0)` })
          .where(and(eq(importJob.id, id), eq(importJob.status, "running"))),
      )
      .pipe(Effect.ignore);

  /**
   * A recipe whose source gave no nutrition gets the model's estimate from its
   * ingredients, flagged for the cook to check. No model, or a failed or slow
   * estimate, leaves the macros blank rather than failing the import.
   */
  const withMacros = <A extends { readonly recipe: ExtractedRecipe }>(imported: A) =>
    Effect.gen(function* () {
      const recipe = imported.recipe;
      const lines = recipe.ingredients
        .map((l) => l.line.trim().slice(0, RECIPE_LIMITS.line))
        .filter((l) => l !== "")
        .slice(0, RECIPE_LIMITS.ingredients);
      if (recipe.macros !== undefined || !model.available || lines.length === 0) return imported;
      const macros = yield* model
        .estimateMacros({
          title: recipe.title?.slice(0, RECIPE_LIMITS.title) ?? null,
          servings:
            recipe.servings !== null &&
            recipe.servings >= 1 &&
            recipe.servings <= RECIPE_LIMITS.servings
              ? Math.round(recipe.servings)
              : null,
          ingredients: lines,
        })
        .pipe(
          Effect.timeoutOrElse({ duration: MACRO_TIMEOUT, orElse: () => Effect.succeed(null) }),
          Effect.catchCause((cause) =>
            Effect.logInfo("Import macro estimate skipped", cause).pipe(Effect.as(null)),
          ),
        );
      if (macros === null) return imported;
      return {
        ...imported,
        recipe: { ...recipe, macros, unsure: [...recipe.unsure, "macros" as const] },
      };
    });

  const work = Effect.fn("Imports.work")(function* (row: JobRow) {
    // A cancel that landed between the claim and now: don't spend a model call.
    if (yield* cancelled(row.id)) return yield* Effect.interrupt;
    const { imported, photoKey } = yield* Effect.gen(function* () {
      const imported = yield* importers.run({
        source: row.source as ImportSource,
        url: row.sourceUrl,
        text: row.inputText,
      });
      // The hero image becomes the cover photo. One that won't fetch or decode
      // in time leaves the draft without a photo rather than failing it. A
      // photo no recipe ends up using is removed by the photo cleanup.
      const imageUrl = imported.recipe.imageUrl;
      const photoKey =
        imageUrl === null
          ? null
          : yield* photos.fromUrl(row.ownerId as UserId, imageUrl).pipe(
              Effect.map((photo): string | null => photo.id),
              Effect.timeoutOrElse({ duration: PHOTO_TIMEOUT, orElse: () => Effect.succeed(null) }),
              Effect.catchCause((cause) =>
                Effect.logInfo("Import photo skipped", { id: row.id }, cause).pipe(Effect.as(null)),
              ),
            );
      return { imported: yield* withMacros(imported), photoKey };
    }).pipe(
      Effect.timeoutOrElse({
        duration: JOB_TIMEOUT,
        orElse: () => Effect.fail(new ImportFailed({ code: "timeout" })),
      }),
    );
    const link = imported.sourceUrl ?? row.sourceUrl;
    const draft = toDraft(imported.recipe, {
      source: row.source as ImportSource,
      sourceUrl: link === null ? null : normalizeUrl(link),
      photoKey,
    });
    return { imported, draft };
  });

  /** Runs one claimed job to a result, recording failures as plain codes. */
  const process = Effect.fn("Imports.process")(function* (row: JobRow) {
    // Interrupted by a cancel, the row is already cancelled and stays so. By a
    // shutdown, it goes back in the queue for the next worker.
    const fiber = yield* FiberMap.run(
      running,
      row.id,
      work(row).pipe(Effect.onInterrupt(() => requeue(row.id))),
    );
    const exit = yield* Fiber.await(fiber);
    if (Exit.isSuccess(exit)) {
      const { imported, draft } = exit.value;
      yield* finish(row.id, {
        status: "done",
        draft,
        extractor: imported.extractor,
        rawContent: imported.raw,
        model: imported.usage?.model ?? null,
        inputTokens: imported.usage?.inputTokens ?? null,
        outputTokens: imported.usage?.outputTokens ?? null,
      });
      return;
    }
    const cause = exit.cause;
    // Cancelled: the row already says so.
    if (Cause.hasInterrupts(cause)) return;
    const failure = Cause.findErrorOption(cause);
    // A DbError here is an outage, not a reason to show the cook.
    if (Option.isSome(failure) && failure.value._tag === "ImportFailed") {
      yield* finish(row.id, {
        status: "failed",
        errorCode: failure.value.code,
        rawContent: failure.value.raw ?? null,
      });
      return;
    }
    yield* Effect.logError("Import failed unexpectedly", { id: row.id }, cause);
    yield* finish(row.id, { status: "failed", errorCode: "unavailable" });
  });

  /** Requeues jobs a stopped worker left running, and gives up on ones that keep failing. */
  const recover = Effect.fn("Imports.recover")(function* () {
    const before = new Date(Date.now() - Duration.toMillis(STALE_AFTER));
    const stale = and(eq(importJob.status, "running"), lt(importJob.startedAt, before));
    yield* db.use((d) =>
      d
        .update(importJob)
        .set({ status: "failed", errorCode: "unavailable", finishedAt: new Date() })
        .where(and(stale, sql`${importJob.attempts} >= ${MAX_ATTEMPTS}`)),
    );
    yield* db.use((d) =>
      d
        .update(importJob)
        .set({ status: "queued" })
        .where(and(stale, lt(importJob.attempts, MAX_ATTEMPTS))),
    );
  });

  /** One worker: claim, run, repeat; idle until woken or the next poll. */
  const worker = Effect.gen(function* () {
    const row = yield* claim;
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

  return { start, get, cancel, save, recover, worker };
});

/** Distill jobs: start, poll, cancel and save. Every read and write is scoped to one owner. */
export class Imports extends Context.Service<Imports, Effect.Success<typeof make>>()(
  "cauldron/api/Imports",
) {
  static readonly layer = Layer.effect(Imports, make).pipe(
    Layer.provide([Recipes.layer, Importers.layer, Photos.layer]),
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
