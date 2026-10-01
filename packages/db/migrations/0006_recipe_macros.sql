ALTER TABLE "recipe" ADD COLUMN "calories" integer;--> statement-breakpoint
ALTER TABLE "recipe" ADD COLUMN "protein_grams" numeric(7, 1);--> statement-breakpoint
ALTER TABLE "recipe" ADD COLUMN "carbs_grams" numeric(7, 1);--> statement-breakpoint
ALTER TABLE "recipe" ADD COLUMN "fat_grams" numeric(7, 1);--> statement-breakpoint
ALTER TABLE "recipe" ADD CONSTRAINT "recipe_macros_nonnegative" CHECK (coalesce("recipe"."calories", 0) >= 0 and coalesce("recipe"."protein_grams", 0) >= 0 and coalesce("recipe"."carbs_grams", 0) >= 0 and coalesce("recipe"."fat_grams", 0) >= 0);