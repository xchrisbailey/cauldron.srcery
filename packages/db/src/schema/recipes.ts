import { sql } from "drizzle-orm";
import {
  boolean,
  check,
  date,
  index,
  integer,
  numeric,
  pgEnum,
  pgTable,
  primaryKey,
  text,
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
// exact numerics so scaling and conversion don't accumulate float error.

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
    /** Storage key of the cover photo (#12). */
    photoKey: text("photo_key"),
    notes: text("notes"),
    ...timestamps(),
    deletedAt: timestampMs("deleted_at"),
  },
  (t) => [
    // Keyset pagination of a user's recipes, newest first.
    index("recipe_owner_created_idx").on(t.ownerId, t.createdAt.desc(), t.id.desc()),
    check("recipe_servings_positive", sql`${t.servings} is null or ${t.servings} > 0`),
  ],
);

export const recipeIngredient = pgTable(
  "recipe_ingredient",
  {
    id: id(),
    ownerId: ownerId(),
    recipeId: uuid("recipe_id")
      .notNull()
      .references(() => recipe.id, { onDelete: "cascade" }),
    position: integer("position").notNull(),
    /** Section heading this line sits under, e.g. "For the sauce". */
    section: text("section"),
    quantityMin: numeric("quantity_min", { mode: "number" }),
    quantityMax: numeric("quantity_max", { mode: "number" }),
    /** Normalized unit code from the shared unit catalog. */
    unit: text("unit"),
    item: text("item").notNull(),
    /** Preparation note, e.g. "finely chopped". */
    note: text("note"),
    optional: boolean("optional").notNull().default(false),
    /** A second measure, e.g. the "(190g)" in "1 1/2 cups (190g) flour". */
    altQuantityMin: numeric("alt_quantity_min", { mode: "number" }),
    altQuantityMax: numeric("alt_quantity_max", { mode: "number" }),
    altUnit: text("alt_unit"),
    /** The line exactly as written. */
    originalLine: text("original_line").notNull(),
    /** Reserved for the nutrition database the tracker will use (#23). */
    foodId: uuid("food_id"),
    ...timestamps(),
  },
  (t) => [
    uniqueIndex("recipe_ingredient_position_idx").on(t.recipeId, t.position),
    index("recipe_ingredient_owner_idx").on(t.ownerId),
    check(
      "recipe_ingredient_range",
      sql`${t.quantityMax} is null or (${t.quantityMin} is not null and ${t.quantityMax} >= ${t.quantityMin})`,
    ),
  ],
);

export const recipeStep = pgTable(
  "recipe_step",
  {
    id: id(),
    ownerId: ownerId(),
    recipeId: uuid("recipe_id")
      .notNull()
      .references(() => recipe.id, { onDelete: "cascade" }),
    position: integer("position").notNull(),
    section: text("section"),
    text: text("text").notNull(),
    timerSeconds: integer("timer_seconds"),
    ...timestamps(),
  },
  (t) => [
    uniqueIndex("recipe_step_position_idx").on(t.recipeId, t.position),
    index("recipe_step_owner_idx").on(t.ownerId),
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
  (t) => [uniqueIndex("tag_owner_name_idx").on(t.ownerId, sql`lower(${t.name})`)],
);

export const recipeTag = pgTable(
  "recipe_tag",
  {
    ownerId: ownerId(),
    recipeId: uuid("recipe_id")
      .notNull()
      .references(() => recipe.id, { onDelete: "cascade" }),
    tagId: uuid("tag_id")
      .notNull()
      .references(() => tag.id, { onDelete: "cascade" }),
    createdAt: timestampMs("created_at").notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.recipeId, t.tagId] }), index("recipe_tag_tag_idx").on(t.tagId)],
);

export const mealPlanEntry = pgTable(
  "meal_plan_entry",
  {
    id: id(),
    ownerId: ownerId(),
    date: date("date", { mode: "string" }).notNull(),
    slot: mealSlot("slot").notNull(),
    /** Null for a free-text item ("leftovers"), or when the recipe is deleted. */
    recipeId: uuid("recipe_id").references(() => recipe.id, { onDelete: "set null" }),
    /** Free-text item, or the recipe's title when it was planned. */
    title: text("title").notNull(),
    servings: integer("servings"),
    position: integer("position").notNull().default(0),
    ...timestamps(),
  },
  (t) => [index("meal_plan_owner_date_idx").on(t.ownerId, t.date)],
);

export const gatherItem = pgTable(
  "gather_item",
  {
    id: id(),
    ownerId: ownerId(),
    /** Monday of the week this list belongs to. */
    weekStart: date("week_start", { mode: "string" }).notNull(),
    item: text("item").notNull(),
    quantityMin: numeric("quantity_min", { mode: "number" }),
    quantityMax: numeric("quantity_max", { mode: "number" }),
    unit: text("unit"),
    /** Store aisle for grouping, e.g. "produce". */
    aisle: text("aisle"),
    checked: boolean("checked").notNull().default(false),
    /** Added by hand rather than gathered from the week's recipes. */
    manual: boolean("manual").notNull().default(false),
    /** Recipes this item was gathered from. */
    sourceRecipeIds: uuid("source_recipe_ids")
      .array()
      .notNull()
      .default(sql`'{}'::uuid[]`),
    position: integer("position").notNull().default(0),
    ...timestamps(),
  },
  (t) => [index("gather_item_owner_week_idx").on(t.ownerId, t.weekStart)],
);
