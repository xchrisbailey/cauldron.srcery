import { sql } from "drizzle-orm";
import {
  boolean,
  check,
  date,
  foreignKey,
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
import { ActivityLevel, DiarySource, Goal, HeightUnit, Sex, WeightUnit } from "@cauldron/shared";
import { user } from "./auth.ts";
import { timestamps } from "./columns.ts";
import { mealSlot, recipe } from "./recipes.ts";

// The tracker (#23): diary entries, daily targets, the body profile they come
// from, and weigh-ins. Everything is stored in metric.

const ownerId = () =>
  text("owner_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" });

const grams = (name: string) => numeric(name, { precision: 7, scale: 1, mode: "number" });

export const diarySource = pgEnum("diary_source", DiarySource.literals);
export const sex = pgEnum("sex", Sex.literals);
export const activityLevel = pgEnum("activity_level", ActivityLevel.literals);
export const goal = pgEnum("goal", Goal.literals);
export const weightUnit = pgEnum("weight_unit", WeightUnit.literals);
export const heightUnit = pgEnum("height_unit", HeightUnit.literals);

/**
 * Something eaten. Calories and macros are per serving and copied when it's
 * logged, so editing the recipe it came from never changes a logged day.
 */
export const diaryEntry = pgTable(
  "diary_entry",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    ownerId: ownerId(),
    date: date("date", { mode: "string" }).notNull(),
    slot: mealSlot("slot").notNull(),
    name: text("name").notNull(),
    amount: text("amount"),
    servings: numeric("servings", { precision: 7, scale: 2, mode: "number" }).notNull(),
    calories: integer("calories"),
    proteinGrams: grams("protein_grams"),
    carbsGrams: grams("carbs_grams"),
    fatGrams: grams("fat_grams"),
    source: diarySource("source").notNull(),
    /** Where it was logged from. Cleared, not cascaded, when the recipe is deleted. */
    recipeId: uuid("recipe_id"),
    position: integer("position").notNull().default(0),
    ...timestamps(),
  },
  (t) => [
    // The migration hand-edits this to `ON DELETE SET NULL (recipe_id)`, as
    // for meal_plan_entry: deleting a recipe keeps the entry and its owner.
    foreignKey({
      columns: [t.recipeId, t.ownerId],
      foreignColumns: [recipe.id, recipe.ownerId],
      name: "diary_entry_recipe_owner_fk",
    }).onDelete("set null"),
    index("diary_entry_owner_date_idx").on(t.ownerId, t.date),
    index("diary_entry_recipe_idx").on(t.recipeId),
    check("diary_entry_servings_positive", sql`${t.servings} > 0`),
    check(
      "diary_entry_macros_nonnegative",
      sql`coalesce(${t.calories}, 0) >= 0 and coalesce(${t.proteinGrams}, 0) >= 0 and coalesce(${t.carbsGrams}, 0) >= 0 and coalesce(${t.fatGrams}, 0) >= 0`,
    ),
  ],
);

/** What the calculator needs, and how the cook likes weights and heights shown. One per user. */
export const bodyProfile = pgTable("body_profile", {
  ownerId: ownerId().primaryKey(),
  sex: sex("sex").notNull(),
  birthDate: date("birth_date", { mode: "string" }).notNull(),
  heightCm: numeric("height_cm", { precision: 4, scale: 1, mode: "number" }).notNull(),
  activity: activityLevel("activity").notNull(),
  goal: goal("goal").notNull(),
  weeklyRateKg: numeric("weekly_rate_kg", { precision: 3, scale: 2, mode: "number" }).notNull(),
  proteinPerKg: numeric("protein_per_kg", { precision: 3, scale: 1, mode: "number" }).notNull(),
  fatShare: numeric("fat_share", { precision: 3, scale: 2, mode: "number" }).notNull(),
  weightUnit: weightUnit("weight_unit").notNull(),
  heightUnit: heightUnit("height_unit").notNull(),
  ...timestamps(),
});

/** Daily targets. One per user. */
export const trackerTargets = pgTable(
  "tracker_targets",
  {
    ownerId: ownerId().primaryKey(),
    calories: integer("calories").notNull(),
    protein: integer("protein").notNull(),
    carbs: integer("carbs").notNull(),
    fat: integer("fat").notNull(),
    /** Typed in by hand rather than calculated; kept through recalculations unless replaced. */
    caloriesOverridden: boolean("calories_overridden").notNull().default(false),
    proteinOverridden: boolean("protein_overridden").notNull().default(false),
    carbsOverridden: boolean("carbs_overridden").notNull().default(false),
    fatOverridden: boolean("fat_overridden").notNull().default(false),
    /** The day of the last weekly check-in (#118). */
    checkedInOn: date("checked_in_on", { mode: "string" }),
    ...timestamps(),
  },
  (t) => [
    check(
      "tracker_targets_nonnegative",
      sql`${t.calories} >= 0 and ${t.protein} >= 0 and ${t.carbs} >= 0 and ${t.fat} >= 0`,
    ),
  ],
);

/** One weight a day; logging again replaces it. */
export const weighIn = pgTable(
  "weigh_in",
  {
    ownerId: ownerId(),
    date: date("date", { mode: "string" }).notNull(),
    weightKg: numeric("weight_kg", { precision: 5, scale: 2, mode: "number" }).notNull(),
    ...timestamps(),
  },
  (t) => [
    primaryKey({ columns: [t.ownerId, t.date] }),
    check("weigh_in_weight_positive", sql`${t.weightKg} > 0`),
  ],
);

/** A starred food (#116): a snapshot of an entry, to log again in one tap. */
export const trackerFavourite = pgTable(
  "tracker_favourite",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    ownerId: ownerId(),
    /** `quickFoodKey`: the recipe, or the lowercased name and amount. One favourite per key. */
    key: text("key").notNull(),
    name: text("name").notNull(),
    amount: text("amount"),
    servings: numeric("servings", { precision: 7, scale: 2, mode: "number" }).notNull(),
    calories: integer("calories"),
    proteinGrams: grams("protein_grams"),
    carbsGrams: grams("carbs_grams"),
    fatGrams: grams("fat_grams"),
    source: diarySource("source").notNull(),
    recipeId: uuid("recipe_id"),
    ...timestamps(),
  },
  (t) => [
    // Hand-edited to `ON DELETE SET NULL (recipe_id)` in the migration, like diary_entry.
    foreignKey({
      columns: [t.recipeId, t.ownerId],
      foreignColumns: [recipe.id, recipe.ownerId],
      name: "tracker_favourite_recipe_owner_fk",
    }).onDelete("set null"),
    uniqueIndex("tracker_favourite_owner_key_idx").on(t.ownerId, t.key),
    index("tracker_favourite_recipe_idx").on(t.recipeId),
    check("tracker_favourite_servings_positive", sql`${t.servings} > 0`),
    check(
      "tracker_favourite_macros_nonnegative",
      sql`coalesce(${t.calories}, 0) >= 0 and coalesce(${t.proteinGrams}, 0) >= 0 and coalesce(${t.carbsGrams}, 0) >= 0 and coalesce(${t.fatGrams}, 0) >= 0`,
    ),
  ],
);
