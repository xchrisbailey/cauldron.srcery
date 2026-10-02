CREATE TYPE "public"."activity_level" AS ENUM('sedentary', 'light', 'moderate', 'active', 'veryActive');--> statement-breakpoint
CREATE TYPE "public"."diary_source" AS ENUM('described', 'recipe', 'manual');--> statement-breakpoint
CREATE TYPE "public"."goal" AS ENUM('lose', 'maintain', 'gain');--> statement-breakpoint
CREATE TYPE "public"."height_unit" AS ENUM('cm', 'ftin');--> statement-breakpoint
CREATE TYPE "public"."sex" AS ENUM('female', 'male', 'unspecified');--> statement-breakpoint
CREATE TYPE "public"."weight_unit" AS ENUM('kg', 'lb');--> statement-breakpoint
CREATE TABLE "body_profile" (
	"owner_id" text PRIMARY KEY NOT NULL,
	"sex" "sex" NOT NULL,
	"birth_date" date NOT NULL,
	"height_cm" numeric(4, 1) NOT NULL,
	"activity" "activity_level" NOT NULL,
	"goal" "goal" NOT NULL,
	"weekly_rate_kg" numeric(3, 2) NOT NULL,
	"protein_per_kg" numeric(3, 1) NOT NULL,
	"fat_share" numeric(3, 2) NOT NULL,
	"weight_unit" "weight_unit" NOT NULL,
	"height_unit" "height_unit" NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "diary_entry" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"date" date NOT NULL,
	"slot" "meal_slot" NOT NULL,
	"name" text NOT NULL,
	"amount" text,
	"servings" numeric(7, 2) NOT NULL,
	"calories" integer,
	"protein_grams" numeric(7, 1),
	"carbs_grams" numeric(7, 1),
	"fat_grams" numeric(7, 1),
	"source" "diary_source" NOT NULL,
	"recipe_id" uuid,
	"position" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "diary_entry_servings_positive" CHECK ("diary_entry"."servings" > 0),
	CONSTRAINT "diary_entry_macros_nonnegative" CHECK (coalesce("diary_entry"."calories", 0) >= 0 and coalesce("diary_entry"."protein_grams", 0) >= 0 and coalesce("diary_entry"."carbs_grams", 0) >= 0 and coalesce("diary_entry"."fat_grams", 0) >= 0)
);
--> statement-breakpoint
CREATE TABLE "tracker_targets" (
	"owner_id" text PRIMARY KEY NOT NULL,
	"calories" integer NOT NULL,
	"protein" integer NOT NULL,
	"carbs" integer NOT NULL,
	"fat" integer NOT NULL,
	"calories_overridden" boolean DEFAULT false NOT NULL,
	"protein_overridden" boolean DEFAULT false NOT NULL,
	"carbs_overridden" boolean DEFAULT false NOT NULL,
	"fat_overridden" boolean DEFAULT false NOT NULL,
	"checked_in_on" date,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tracker_targets_nonnegative" CHECK ("tracker_targets"."calories" >= 0 and "tracker_targets"."protein" >= 0 and "tracker_targets"."carbs" >= 0 and "tracker_targets"."fat" >= 0)
);
--> statement-breakpoint
CREATE TABLE "weigh_in" (
	"owner_id" text NOT NULL,
	"date" date NOT NULL,
	"weight_kg" numeric(5, 2) NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "weigh_in_owner_id_date_pk" PRIMARY KEY("owner_id","date"),
	CONSTRAINT "weigh_in_weight_positive" CHECK ("weigh_in"."weight_kg" > 0)
);
--> statement-breakpoint
ALTER TABLE "body_profile" ADD CONSTRAINT "body_profile_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "diary_entry" ADD CONSTRAINT "diary_entry_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "diary_entry" ADD CONSTRAINT "diary_entry_recipe_owner_fk" FOREIGN KEY ("recipe_id","owner_id") REFERENCES "public"."recipe"("id","owner_id") ON DELETE set null ("recipe_id") ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tracker_targets" ADD CONSTRAINT "tracker_targets_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "weigh_in" ADD CONSTRAINT "weigh_in_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "diary_entry_owner_date_idx" ON "diary_entry" USING btree ("owner_id","date");--> statement-breakpoint
CREATE INDEX "diary_entry_recipe_idx" ON "diary_entry" USING btree ("recipe_id");