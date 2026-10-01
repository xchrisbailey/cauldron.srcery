CREATE TABLE "pantry_item" (
	"owner_id" text NOT NULL,
	"item_key" text NOT NULL,
	"created_at" timestamp (3) with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "pantry_item_owner_id_item_key_pk" PRIMARY KEY("owner_id","item_key")
);
--> statement-breakpoint
ALTER TABLE "pantry_item" ADD CONSTRAINT "pantry_item_owner_id_user_id_fk" FOREIGN KEY ("owner_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;