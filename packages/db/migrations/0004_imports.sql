CREATE TYPE "public"."import_status" AS ENUM('queued', 'running', 'done', 'failed', 'cancelled', 'saved');--> statement-breakpoint
CREATE TABLE "import_job" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"status" "import_status" DEFAULT 'queued' NOT NULL,
	"source" "source_platform" NOT NULL,
	"source_url" text,
	"input_text" text,
	"raw_content" text,
	"draft" jsonb,
	"error_code" text,
	"extractor" text,
	"attempts" integer DEFAULT 0 NOT NULL,
	"recipe_id" uuid,
	"model" text,
	"input_tokens" integer,
	"output_tokens" integer,
	"started_at" timestamp (3) with time zone,
	"finished_at" timestamp (3) with time zone,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "import_job_input_check" CHECK (("import_job"."source_url" is not null) <> ("import_job"."input_text" is not null))
);
--> statement-breakpoint
ALTER TABLE "import_job" ADD CONSTRAINT "import_job_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "import_job_queued_idx" ON "import_job" USING btree ("created_at") WHERE "import_job"."status" = 'queued';--> statement-breakpoint
CREATE INDEX "import_job_owner_created_idx" ON "import_job" USING btree ("owner_id","created_at" DESC NULLS LAST);