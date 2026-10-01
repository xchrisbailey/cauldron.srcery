import { sql } from "drizzle-orm";
import { check, index, integer, jsonb, pgEnum, pgTable, text, uuid } from "drizzle-orm/pg-core";
import { ImportStatus } from "@cauldron/shared";
import { user } from "./auth.ts";
import { timestampMs, timestamps } from "./columns.ts";
import { sourcePlatform } from "./recipes.ts";

export const importStatus = pgEnum("import_status", ImportStatus.literals);

/**
 * One Distill (#13): a link or pasted text on its way to a draft recipe. The
 * worker claims queued rows with `for update skip locked`, so this table is
 * also the job queue. Nothing here is a recipe until the cook saves the draft.
 */
export const importJob = pgTable(
  "import_job",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    ownerId: text("owner_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    status: importStatus("status").notNull().default("queued"),
    /** What kind of source this is: web, instagram, tiktok or text. Never manual. */
    source: sourcePlatform("source").notNull(),
    /** The link as given, for links. */
    sourceUrl: text("source_url"),
    /** The text as pasted, for pasted text. */
    inputText: text("input_text"),
    /** What the importer read (page text, caption), kept for debugging and for #17. */
    rawContent: text("raw_content"),
    /** The draft recipe (`ImportDraft` in `@cauldron/shared`). */
    draft: jsonb("draft"),
    /** Why it failed, from `ImportFailureCode`. `spokenOnly` marks posts #17 can retry. */
    errorCode: text("error_code"),
    /** Which extractor produced the draft, e.g. "json-ld", "text", "model". */
    extractor: text("extractor"),
    attempts: integer("attempts").notNull().default(0),
    /** The recipe the draft was saved as. */
    recipeId: uuid("recipe_id"),
    // Cost log: the model call(s) a job made, if any.
    model: text("model"),
    inputTokens: integer("input_tokens"),
    outputTokens: integer("output_tokens"),
    startedAt: timestampMs("started_at"),
    finishedAt: timestampMs("finished_at"),
    ...timestamps(),
  },
  (t) => [
    // The worker's claim: the oldest queued job first.
    index("import_job_queued_idx")
      .on(t.createdAt)
      .where(sql`${t.status} = 'queued'`),
    // Per-user daily caps and de-duplication lookups.
    index("import_job_owner_created_idx").on(t.ownerId, t.createdAt.desc()),
    check(
      "import_job_input_check",
      sql`(${t.sourceUrl} is not null) <> (${t.inputText} is not null)`,
    ),
  ],
);
