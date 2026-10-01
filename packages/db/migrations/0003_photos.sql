CREATE TABLE "photo" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"width" integer NOT NULL,
	"height" integer NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "photo_id_owner_unique" UNIQUE("id","owner_id")
);
--> statement-breakpoint
CREATE TABLE "photo_upload" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_id" text NOT NULL,
	"content_type" text NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
-- Hand-edited: text to uuid needs USING. Nothing set photo_key before #12.
ALTER TABLE "recipe" ALTER COLUMN "photo_key" SET DATA TYPE uuid USING "photo_key"::uuid;--> statement-breakpoint
ALTER TABLE "photo" ADD CONSTRAINT "photo_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "photo_upload" ADD CONSTRAINT "photo_upload_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "photo_created_idx" ON "photo" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "photo_upload_created_idx" ON "photo_upload" USING btree ("created_at");--> statement-breakpoint
ALTER TABLE "recipe" ADD CONSTRAINT "recipe_photo_owner_fk" FOREIGN KEY ("photo_key","owner_id") REFERENCES "public"."photo"("id","owner_id") ON DELETE no action ON UPDATE no action;