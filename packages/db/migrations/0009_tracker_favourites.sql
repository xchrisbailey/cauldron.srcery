CREATE TABLE "tracker_favourite" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"key" text NOT NULL,
	"name" text NOT NULL,
	"amount" text,
	"servings" numeric(7, 2) NOT NULL,
	"calories" integer,
	"protein_grams" numeric(7, 1),
	"carbs_grams" numeric(7, 1),
	"fat_grams" numeric(7, 1),
	"source" "diary_source" NOT NULL,
	"recipe_id" uuid,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tracker_favourite_servings_positive" CHECK ("tracker_favourite"."servings" > 0),
	CONSTRAINT "tracker_favourite_macros_nonnegative" CHECK (coalesce("tracker_favourite"."calories", 0) >= 0 and coalesce("tracker_favourite"."protein_grams", 0) >= 0 and coalesce("tracker_favourite"."carbs_grams", 0) >= 0 and coalesce("tracker_favourite"."fat_grams", 0) >= 0)
);
--> statement-breakpoint
ALTER TABLE "tracker_favourite" ADD CONSTRAINT "tracker_favourite_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tracker_favourite" ADD CONSTRAINT "tracker_favourite_recipe_owner_fk" FOREIGN KEY ("recipe_id","owner_id") REFERENCES "public"."recipe"("id","owner_id") ON DELETE set null ("recipe_id") ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "tracker_favourite_owner_key_idx" ON "tracker_favourite" USING btree ("owner_id","key");--> statement-breakpoint
CREATE INDEX "tracker_favourite_recipe_idx" ON "tracker_favourite" USING btree ("recipe_id");