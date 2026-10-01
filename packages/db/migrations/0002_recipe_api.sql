CREATE TABLE "recipe_cook" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"recipe_id" uuid NOT NULL,
	"cooked_on" date NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "recipe" ADD COLUMN "last_cooked_on" date;--> statement-breakpoint
ALTER TABLE "recipe" ADD COLUMN "search" "tsvector";--> statement-breakpoint
ALTER TABLE "recipe_cook" ADD CONSTRAINT "recipe_cook_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_cook" ADD CONSTRAINT "recipe_cook_recipe_owner_fk" FOREIGN KEY ("recipe_id","owner_id") REFERENCES "public"."recipe"("id","owner_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "recipe_cook_recipe_day_idx" ON "recipe_cook" USING btree ("recipe_id","cooked_on" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "recipe_owner_title_idx" ON "recipe" USING btree ("owner_id",lower("title"),"id") WHERE "recipe"."deleted_at" is null;--> statement-breakpoint
CREATE INDEX "recipe_owner_cooked_idx" ON "recipe" USING btree ("owner_id",(coalesce("last_cooked_on", '0001-01-01'::date)) desc,"id" DESC NULLS LAST) WHERE "recipe"."deleted_at" is null;--> statement-breakpoint
CREATE INDEX "recipe_search_idx" ON "recipe" USING gin ("search");--> statement-breakpoint
-- Hand-written: the search document for one recipe. The API (and the seed)
-- set recipe.search from it after writing a recipe, its ingredients or tags.
CREATE FUNCTION "recipe_search_document"("recipe_id" uuid) RETURNS tsvector
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT
    setweight(to_tsvector('english', coalesce(r.title, '')), 'A')
    || setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(t.name, ' ') FROM recipe_tag rt JOIN tag t ON t.id = rt.tag_id WHERE rt.recipe_id = r.id),
      '')), 'B')
    || setweight(to_tsvector('english', coalesce(
      (SELECT string_agg(i.item, ' ') FROM recipe_ingredient i WHERE i.recipe_id = r.id),
      '')), 'C')
    || setweight(to_tsvector('english', coalesce(r.description, '')), 'D')
  FROM recipe r WHERE r.id = $1
$$;--> statement-breakpoint
UPDATE "recipe" SET "search" = "recipe_search_document"("id");
