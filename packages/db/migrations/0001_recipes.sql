CREATE TYPE "public"."meal_slot" AS ENUM('breakfast', 'lunch', 'dinner', 'snack');--> statement-breakpoint
CREATE TYPE "public"."source_platform" AS ENUM('web', 'instagram', 'tiktok', 'manual', 'text');--> statement-breakpoint
CREATE TYPE "public"."tag_kind" AS ENUM('cuisine', 'meal', 'diet', 'other');--> statement-breakpoint
CREATE TABLE "gather_item" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"week_start" date NOT NULL,
	"item" text NOT NULL,
	"quantity_min" numeric,
	"quantity_max" numeric,
	"unit" text,
	"aisle" text,
	"checked" boolean DEFAULT false NOT NULL,
	"manual" boolean DEFAULT false NOT NULL,
	"source_recipe_ids" uuid[] DEFAULT '{}'::uuid[] NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "meal_plan_entry" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"date" date NOT NULL,
	"slot" "meal_slot" NOT NULL,
	"recipe_id" uuid,
	"title" text NOT NULL,
	"servings" integer,
	"position" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "recipe" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"title" text NOT NULL,
	"description" text,
	"servings" integer,
	"prep_minutes" integer,
	"cook_minutes" integer,
	"total_minutes" integer,
	"source_platform" "source_platform" DEFAULT 'manual' NOT NULL,
	"source_url" text,
	"source_author" text,
	"source_fetched_at" timestamp (3) with time zone,
	"photo_key" text,
	"notes" text,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp (3) with time zone,
	CONSTRAINT "recipe_servings_positive" CHECK ("recipe"."servings" is null or "recipe"."servings" > 0)
);
--> statement-breakpoint
CREATE TABLE "recipe_ingredient" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"recipe_id" uuid NOT NULL,
	"position" integer NOT NULL,
	"section" text,
	"quantity_min" numeric,
	"quantity_max" numeric,
	"unit" text,
	"item" text NOT NULL,
	"note" text,
	"optional" boolean DEFAULT false NOT NULL,
	"alt_quantity_min" numeric,
	"alt_quantity_max" numeric,
	"alt_unit" text,
	"original_line" text NOT NULL,
	"food_id" uuid,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recipe_ingredient_range" CHECK ("recipe_ingredient"."quantity_max" is null or ("recipe_ingredient"."quantity_min" is not null and "recipe_ingredient"."quantity_max" >= "recipe_ingredient"."quantity_min"))
);
--> statement-breakpoint
CREATE TABLE "recipe_step" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"recipe_id" uuid NOT NULL,
	"position" integer NOT NULL,
	"section" text,
	"text" text NOT NULL,
	"timer_seconds" integer,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recipe_step_timer_positive" CHECK ("recipe_step"."timer_seconds" is null or "recipe_step"."timer_seconds" > 0)
);
--> statement-breakpoint
CREATE TABLE "recipe_tag" (
	"owner_id" text NOT NULL,
	"recipe_id" uuid NOT NULL,
	"tag_id" uuid NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recipe_tag_recipe_id_tag_id_pk" PRIMARY KEY("recipe_id","tag_id")
);
--> statement-breakpoint
CREATE TABLE "tag" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"name" text NOT NULL,
	"kind" "tag_kind" DEFAULT 'other' NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "gather_item" ADD CONSTRAINT "gather_item_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "meal_plan_entry" ADD CONSTRAINT "meal_plan_entry_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "meal_plan_entry" ADD CONSTRAINT "meal_plan_entry_recipe_id_recipe_id_fk" FOREIGN KEY ("recipe_id") REFERENCES "public"."recipe"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe" ADD CONSTRAINT "recipe_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_ingredient" ADD CONSTRAINT "recipe_ingredient_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_ingredient" ADD CONSTRAINT "recipe_ingredient_recipe_id_recipe_id_fk" FOREIGN KEY ("recipe_id") REFERENCES "public"."recipe"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_step" ADD CONSTRAINT "recipe_step_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_step" ADD CONSTRAINT "recipe_step_recipe_id_recipe_id_fk" FOREIGN KEY ("recipe_id") REFERENCES "public"."recipe"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_tag" ADD CONSTRAINT "recipe_tag_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_tag" ADD CONSTRAINT "recipe_tag_recipe_id_recipe_id_fk" FOREIGN KEY ("recipe_id") REFERENCES "public"."recipe"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_tag" ADD CONSTRAINT "recipe_tag_tag_id_tag_id_fk" FOREIGN KEY ("tag_id") REFERENCES "public"."tag"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tag" ADD CONSTRAINT "tag_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "gather_item_owner_week_idx" ON "gather_item" USING btree ("owner_id","week_start");--> statement-breakpoint
CREATE INDEX "meal_plan_owner_date_idx" ON "meal_plan_entry" USING btree ("owner_id","date");--> statement-breakpoint
CREATE INDEX "recipe_owner_created_idx" ON "recipe" USING btree ("owner_id","created_at" DESC NULLS LAST,"id" DESC NULLS LAST);--> statement-breakpoint
CREATE UNIQUE INDEX "recipe_ingredient_position_idx" ON "recipe_ingredient" USING btree ("recipe_id","position");--> statement-breakpoint
CREATE INDEX "recipe_ingredient_owner_idx" ON "recipe_ingredient" USING btree ("owner_id");--> statement-breakpoint
CREATE UNIQUE INDEX "recipe_step_position_idx" ON "recipe_step" USING btree ("recipe_id","position");--> statement-breakpoint
CREATE INDEX "recipe_step_owner_idx" ON "recipe_step" USING btree ("owner_id");--> statement-breakpoint
CREATE INDEX "recipe_tag_tag_idx" ON "recipe_tag" USING btree ("tag_id");--> statement-breakpoint
CREATE UNIQUE INDEX "tag_owner_name_idx" ON "tag" USING btree ("owner_id",lower("name"));