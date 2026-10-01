import { sql } from "drizzle-orm";
import {
  boolean,
  check,
  customType,
  date,
  foreignKey,
  index,
  integer,
  numeric,
  pgEnum,
  pgTable,
  primaryKey,
  text,
  unique,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { user } from "./auth.ts";
import { timestampMs, timestamps } from "./columns.ts";

// Every owned row carries owner_id, and deleting the user deletes their data.
// Households (#24) can later swap owner for a household id without reshaping.
const ownerId = () =>
  text("owner_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" });

const id = () => uuid("id").primaryKey().defaultRandom();

// Quantities are a min and an optional max (for ranges like 2–3), stored as
// numeric(12, 4): exact decimals with a fixed scale of four places, so values
// like 1/3 (0.3333) are rounded once on write rather than carried as binary
// floats. The driver hands them back as JS numbers (`mode: "number"`), so
// arithmetic after a read is ordinary float arithmetic; the column type only
// guarantees what is stored. `>= 0` and range checks live on each table.
const quantity = (name: string) => numeric(name, { precision: 12, scale: 4, mode: "number" });

// Ownership is enforced by the database, not just by queries: parents expose
// unique (id, owner_id) and children reference the pair, so a child row can
// never point at another user's recipe, tag or gather item.

/** Postgres full text search document. Written only by SQL (see `recipeSearchDocument` in the API). */
const tsvector = customType<{ data: string }>({ dataType: () => "tsvector" });

export const sourcePlatform = pgEnum("source_platform", [
  "web",
  "instagram",
  "tiktok",
  "manual",
  "text",
]);
export const mealSlot = pgEnum("meal_slot", ["breakfast", "lunch", "dinner", "snack"]);
export const tagKind = pgEnum("tag_kind", ["cuisine", "meal", "diet", "other"]);

export const recipe = pgTable(
  "recipe",
  {
    id: id(),
    ownerId: ownerId(),
    title: text("title").notNull(),
    description: text("description"),
    servings: integer("servings"),
    prepMinutes: integer("prep_minutes"),
    cookMinutes: integer("cook_minutes"),
    totalMinutes: integer("total_minutes"),
    sourcePlatform: sourcePlatform("source_platform").notNull().default("manual"),
    sourceUrl: text("source_url"),
    sourceAuthor: text("source_author"),
    sourceFetchedAt: timestampMs("source_fetched_at"),
    /** Id of the cover photo in `photo` (#12). Duplicates may share one. */
    photoKey: text("photo_key"),
    notes: text("notes"),
    /** The most recent day it was marked as cooked; mirrors the latest `recipe_cook` row. */
    lastCookedOn: date("last_cooked_on", { mode: "string" }),
    /**
     * Title, tags, ingredient items and description, weighted in that order.
     * Recomputed by the API whenever any of them change.
     */
    search: tsvector("search"),
    ...timestamps(),
    deletedAt: timestampMs("deleted_at"),
  },
  (t) => [
    // Target of the composite (recipe_id, owner_id) foreign keys on child tables.
    unique("recipe_id_owner_unique").on(t.id, t.ownerId),
    // Keyset pagination of a user's live recipes, newest first.
    index("recipe_owner_created_idx")
      .on(t.ownerId, t.createdAt.desc(), t.id.desc())
      .where(sql`${t.deletedAt} is null`),
    // Sorting a user's live recipes by title and by last cooked.
    index("recipe_owner_title_idx")
      .on(t.ownerId, sql`lower(${t.title})`, t.id)
      .where(sql`${t.deletedAt} is null`),
    // Never-cooked recipes sort last: the API orders by this same expression.
    index("recipe_owner_cooked_idx")
      .on(t.ownerId, sql`(coalesce(${t.lastCookedOn}, '0001-01-01'::date)) desc`, t.id.desc())
      .where(sql`${t.deletedAt} is null`),
    index("recipe_search_idx").using("gin", t.search),
    check("recipe_servings_positive", sql`${t.servings} is null or ${t.servings} > 0`),
  ],
);

/** Each time a recipe was cooked. `recipe.last_cooked_on` holds the latest. */
export const recipeCook = pgTable(
  "recipe_cook",
  {
    id: id(),
    ownerId: ownerId(),
    recipeId: uuid("recipe_id").notNull(),
    cookedOn: date("cooked_on", { mode: "string" }).notNull(),
    createdAt: timestampMs("created_at").notNull().defaultNow(),
  },
  (t) => [
    foreignKey({
      columns: [t.recipeId, t.ownerId],
      foreignColumns: [recipe.id, recipe.ownerId],
      name: "recipe_cook_recipe_owner_fk",
    }).onDelete("cascade"),
    uniqueIndex("recipe_cook_recipe_day_idx").on(t.recipeId, t.cookedOn.desc()),
  ],
);

export const recipeIngredient = pgTable(
  "recipe_ingredient",
  {
    id: id(),
    ownerId: ownerId(),
    recipeId: uuid("recipe_id").notNull(),
    position: integer("position").notNull(),
    /** Section heading this line sits under, e.g. "For the sauce". */
    section: text("section"),
    quantityMin: quantity("quantity_min"),
    quantityMax: quantity("quantity_max"),
    /** Normalized unit code from the shared unit catalog. */
    unit: text("unit"),
    item: text("item").notNull(),
    /**
     * Normalized merge key from `ingredientKey(item)` in `@cauldron/shared`
     * (lowercase, singular, size words removed). The Gather list (#19) merges
     * lines that share a key, per unit dimension (volume, mass, count): it
     * never adds cups to grams, and keeps one row per dimension.
     */
    itemKey: text("item_key").notNull(),
    /** Preparation note, e.g. "finely chopped". */
    note: text("note"),
    optional: boolean("optional").notNull().default(false),
    /** A second measure, e.g. the "(190g)" in "1 1/2 cups (190g) flour". */
    altQuantityMin: quantity("alt_quantity_min"),
    altQuantityMax: quantity("alt_quantity_max"),
    altUnit: text("alt_unit"),
    /** The line exactly as written. */
    originalLine: text("original_line").notNull(),
    /** Reserved for the nutrition database the tracker will use (#23). */
    foodId: uuid("food_id"),
    ...timestamps(),
  },
  (t) => [
    foreignKey({
      columns: [t.recipeId, t.ownerId],
      foreignColumns: [recipe.id, recipe.ownerId],
      name: "recipe_ingredient_recipe_owner_fk",
    }).onDelete("cascade"),
    uniqueIndex("recipe_ingredient_position_idx").on(t.recipeId, t.position),
    // For the tracker (#23): a user's lines that map to a food.
    index("recipe_ingredient_owner_food_idx").on(t.ownerId, t.foodId),
    check(
      "recipe_ingredient_quantity_check",
      sql`(${t.quantityMin} is null or ${t.quantityMin} >= 0)
        and (${t.quantityMax} is null or (${t.quantityMin} is not null and ${t.quantityMax} >= ${t.quantityMin}))`,
    ),
    check(
      "recipe_ingredient_alt_quantity_check",
      sql`(${t.altQuantityMin} is null or ${t.altQuantityMin} >= 0)
        and (${t.altQuantityMax} is null or (${t.altQuantityMin} is not null and ${t.altQuantityMax} >= ${t.altQuantityMin}))`,
    ),
  ],
);

export const recipeStep = pgTable(
  "recipe_step",
  {
    id: id(),
    ownerId: ownerId(),
    recipeId: uuid("recipe_id").notNull(),
    position: integer("position").notNull(),
    section: text("section"),
    text: text("text").notNull(),
    timerSeconds: integer("timer_seconds"),
    ...timestamps(),
  },
  (t) => [
    foreignKey({
      columns: [t.recipeId, t.ownerId],
      foreignColumns: [recipe.id, recipe.ownerId],
      name: "recipe_step_recipe_owner_fk",
    }).onDelete("cascade"),
    uniqueIndex("recipe_step_position_idx").on(t.recipeId, t.position),
    check("recipe_step_timer_positive", sql`${t.timerSeconds} is null or ${t.timerSeconds} > 0`),
  ],
);

export const tag = pgTable(
  "tag",
  {
    id: id(),
    ownerId: ownerId(),
    name: text("name").notNull(),
    kind: tagKind("kind").notNull().default("other"),
    ...timestamps(),
  },
  (t) => [
    // Target of the composite (tag_id, owner_id) foreign key on recipe_tag.
    unique("tag_id_owner_unique").on(t.id, t.ownerId),
    uniqueIndex("tag_owner_name_idx").on(t.ownerId, sql`lower(${t.name})`),
  ],
);

export const recipeTag = pgTable(
  "recipe_tag",
  {
    ownerId: ownerId(),
    recipeId: uuid("recipe_id").notNull(),
    tagId: uuid("tag_id").notNull(),
    createdAt: timestampMs("created_at").notNull().defaultNow(),
  },
  (t) => [
    primaryKey({ columns: [t.recipeId, t.tagId] }),
    foreignKey({
      columns: [t.recipeId, t.ownerId],
      foreignColumns: [recipe.id, recipe.ownerId],
      name: "recipe_tag_recipe_owner_fk",
    }).onDelete("cascade"),
    foreignKey({
      columns: [t.tagId, t.ownerId],
      foreignColumns: [tag.id, tag.ownerId],
      name: "recipe_tag_tag_owner_fk",
    }).onDelete("cascade"),
    index("recipe_tag_tag_idx").on(t.tagId),
  ],
);

export const mealPlanEntry = pgTable(
  "meal_plan_entry",
  {
    id: id(),
    ownerId: ownerId(),
    date: date("date", { mode: "string" }).notNull(),
    slot: mealSlot("slot").notNull(),
    /** Null for a free-text item ("leftovers"), or when the recipe is deleted. */
    recipeId: uuid("recipe_id"),
    /** Free-text item, or the recipe's title when it was planned. */
    title: text("title").notNull(),
    servings: integer("servings"),
    position: integer("position").notNull().default(0),
    ...timestamps(),
  },
  (t) => [
    // The migration hand-edits this to `ON DELETE SET NULL (recipe_id)`
    // (Postgres 15+), which Drizzle cannot express: a plain `set null` would
    // also null owner_id and fail its NOT NULL. Deleting a recipe clears only
    // recipe_id and keeps the entry and its owner. When recipe_id is null the
    // composite key is not checked (MATCH SIMPLE).
    foreignKey({
      columns: [t.recipeId, t.ownerId],
      foreignColumns: [recipe.id, recipe.ownerId],
      name: "meal_plan_entry_recipe_owner_fk",
    }).onDelete("set null"),
    index("meal_plan_owner_date_idx").on(t.ownerId, t.date),
    index("meal_plan_recipe_idx").on(t.recipeId),
    check("meal_plan_servings_positive", sql`${t.servings} is null or ${t.servings} > 0`),
  ],
);

export const gatherItem = pgTable(
  "gather_item",
  {
    id: id(),
    ownerId: ownerId(),
    /** Monday of the week this list belongs to. */
    weekStart: date("week_start", { mode: "string" }).notNull(),
    item: text("item").notNull(),
    /**
     * Normalized merge key from `ingredientKey(item)`. Gather (#19) merges
     * recipe lines per (item_key, unit dimension): "2 cups flour" and
     * "250 g flour" stay separate rows because cups and grams don't convert
     * without a density, while "1 cup" and "2 tbsp" of it sum in one row.
     */
    itemKey: text("item_key").notNull(),
    quantityMin: quantity("quantity_min"),
    quantityMax: quantity("quantity_max"),
    unit: text("unit"),
    /** Store aisle for grouping, e.g. "produce". */
    aisle: text("aisle"),
    checked: boolean("checked").notNull().default(false),
    /** Added by hand rather than gathered from the week's recipes. */
    manual: boolean("manual").notNull().default(false),
    position: integer("position").notNull().default(0),
    ...timestamps(),
  },
  (t) => [
    // Target of the composite (gather_item_id, owner_id) key on gather_item_source.
    unique("gather_item_id_owner_unique").on(t.id, t.ownerId),
    index("gather_item_owner_week_idx").on(t.ownerId, t.weekStart),
    index("gather_item_owner_week_key_idx").on(t.ownerId, t.weekStart, t.itemKey),
    check(
      "gather_item_quantity_check",
      sql`(${t.quantityMin} is null or ${t.quantityMin} >= 0)
        and (${t.quantityMax} is null or (${t.quantityMin} is not null and ${t.quantityMax} >= ${t.quantityMin}))`,
    ),
  ],
);

/** The recipes a gather item was merged from, and how much each contributed. */
export const gatherItemSource = pgTable(
  "gather_item_source",
  {
    id: id(),
    ownerId: ownerId(),
    gatherItemId: uuid("gather_item_id").notNull(),
    recipeId: uuid("recipe_id").notNull(),
    quantityMin: quantity("quantity_min"),
    quantityMax: quantity("quantity_max"),
    unit: text("unit"),
  },
  (t) => [
    foreignKey({
      columns: [t.gatherItemId, t.ownerId],
      foreignColumns: [gatherItem.id, gatherItem.ownerId],
      name: "gather_item_source_item_owner_fk",
    }).onDelete("cascade"),
    // Deleting a recipe removes the contributions it made.
    foreignKey({
      columns: [t.recipeId, t.ownerId],
      foreignColumns: [recipe.id, recipe.ownerId],
      name: "gather_item_source_recipe_owner_fk",
    }).onDelete("cascade"),
    index("gather_item_source_item_idx").on(t.gatherItemId),
    index("gather_item_source_recipe_idx").on(t.recipeId),
    check(
      "gather_item_source_quantity_check",
      sql`(${t.quantityMin} is null or ${t.quantityMin} >= 0)
        and (${t.quantityMax} is null or (${t.quantityMin} is not null and ${t.quantityMax} >= ${t.quantityMin}))`,
    ),
  ],
);

/**
 * A processed photo. Its WebP variants live in storage under
 * `photos/<owner_id>/<id>/<variant>.webp`. Photos no recipe points at are
 * removed by the cleanup job after a grace period.
 */
export const photo = pgTable(
  "photo",
  {
    id: id(),
    ownerId: ownerId(),
    width: integer("width").notNull(),
    height: integer("height").notNull(),
    createdAt: timestampMs("created_at").notNull().defaultNow(),
  },
  (t) => [index("photo_owner_idx").on(t.ownerId), index("photo_created_idx").on(t.createdAt)],
);

/** An upload the client was given a URL for and hasn't finished yet. */
export const photoUpload = pgTable(
  "photo_upload",
  {
    id: id(),
    ownerId: ownerId(),
    contentType: text("content_type").notNull(),
    createdAt: timestampMs("created_at").notNull().defaultNow(),
  },
  (t) => [index("photo_upload_created_idx").on(t.createdAt)],
);
