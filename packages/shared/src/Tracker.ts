import { Schema } from "effect";
import { validation } from "./copy.ts";
import { MealSlot } from "./MealPlan.ts";
import {
  LocalDate,
  Macros,
  MacrosInput,
  MACRO_KEYS,
  type MacroKey,
  RECIPE_LIMITS,
  RecipeId,
} from "./Recipe.ts";

// The tracker (#23): what was actually eaten each day, the daily targets it's
// measured against, the body profile those targets come from, and weigh-ins.
// Diary entries copy their calories and macros when logged, so editing or
// banishing a recipe later never rewrites a logged day.

export const DiaryEntryId = Schema.String.check(Schema.isUUID()).pipe(Schema.brand("DiaryEntryId"));
export type DiaryEntryId = typeof DiaryEntryId.Type;

/** Where an entry came from: described in words (#114), a recipe (#115), or typed in by hand. */
export const DIARY_SOURCES = ["described", "recipe", "manual"] as const;
export const DiarySource = Schema.Literals(DIARY_SOURCES);
export type DiarySource = typeof DiarySource.Type;

export const SEXES = ["female", "male", "unspecified"] as const;
export const Sex = Schema.Literals(SEXES);
export type Sex = typeof Sex.Type;

export const ACTIVITY_LEVELS = ["sedentary", "light", "moderate", "active", "veryActive"] as const;
export const ActivityLevel = Schema.Literals(ACTIVITY_LEVELS);
export type ActivityLevel = typeof ActivityLevel.Type;

export const GOALS = ["lose", "maintain", "gain"] as const;
export const Goal = Schema.Literals(GOALS);
export type Goal = typeof Goal.Type;

export const WEIGHT_UNITS = ["kg", "lb"] as const;
export const WeightUnit = Schema.Literals(WEIGHT_UNITS);
export type WeightUnit = typeof WeightUnit.Type;

export const HEIGHT_UNITS = ["cm", "ftin"] as const;
export const HeightUnit = Schema.Literals(HEIGHT_UNITS);
export type HeightUnit = typeof HeightUnit.Type;

export const TRACKER_LIMITS = {
  name: RECIPE_LIMITS.title,
  amount: 100,
  /** Servings on one entry. Fractions are fine: half a portion is 0.5. */
  servings: 100,
  /** Entries on one day. */
  perDay: 100,
  /** Entries in one batch add, such as one described meal or a copied day. */
  batch: 100,
  /** The longest range one read may cover: a year and a day, for leap years. */
  rangeDays: 367,
  /** Stored in kilograms. */
  weightKg: { min: 20, max: 400 },
  heightCm: { min: 100, max: 250 },
  /** Kilograms a week to lose or gain. */
  weeklyRateKg: { min: 0, max: 1 },
  proteinPerKg: { min: 1.2, max: 3 },
  fatShare: { min: 0.2, max: 0.4 },
  /** Daily targets. */
  calories: { min: 800, max: 10000 },
  grams: { min: 0, max: 1000 },
} as const;

const between = (minimum: number, maximum: number) =>
  Schema.Finite.annotate({ message: validation.numberBetween(minimum, maximum).text }).check(
    Schema.isBetween(
      { minimum, maximum },
      { message: validation.numberBetween(minimum, maximum).text },
    ),
  );

const wholeBetween = (minimum: number, maximum: number) =>
  Schema.Int.annotate({ message: validation.wholeNumber(minimum, maximum).text }).check(
    Schema.isBetween(
      { minimum, maximum },
      { message: validation.wholeNumber(minimum, maximum).text },
    ),
  );

const Name = Schema.Trim.check(
  Schema.isNonEmpty({ message: validation.required.text }),
  Schema.isMaxLength(TRACKER_LIMITS.name, {
    message: validation.tooLong(TRACKER_LIMITS.name).text,
  }),
);

const Amount = Schema.NullOr(
  Schema.Trim.check(
    Schema.isMaxLength(TRACKER_LIMITS.amount, {
      message: validation.tooLong(TRACKER_LIMITS.amount).text,
    }),
  ),
);

const Servings = Schema.Finite.annotate({
  message: validation.numberBetween(0, TRACKER_LIMITS.servings).text,
}).check(
  Schema.isGreaterThan(0, { message: validation.numberBetween(0, TRACKER_LIMITS.servings).text }),
  Schema.isLessThanOrEqualTo(TRACKER_LIMITS.servings, {
    message: validation.numberBetween(0, TRACKER_LIMITS.servings).text,
  }),
);

/** Calories and macros added up, with unknowns counting as nothing. */
export type MacroTotals = Record<MacroKey, number>;
export const MacroTotals = Schema.Struct({
  calories: Schema.Number,
  protein: Schema.Number,
  carbs: Schema.Number,
  fat: Schema.Number,
}).annotate({ identifier: "MacroTotals" });

export const DiaryEntry = Schema.Struct({
  id: DiaryEntryId,
  date: LocalDate,
  slot: MealSlot,
  name: Schema.String,
  /** What was eaten, in words: "2 large", "1 slice". */
  amount: Schema.NullOr(Schema.String),
  servings: Schema.Number,
  /** Per serving, as copied when logged. Unknowns stay null. */
  macros: Macros,
  source: DiarySource,
  /** The recipe it was logged from, while that recipe exists. */
  recipeId: Schema.NullOr(RecipeId),
  /** Order within the day's slot, from 0. */
  position: Schema.Int,
}).annotate({ identifier: "DiaryEntry" });
export type DiaryEntry = typeof DiaryEntry.Type;

export const DiaryEntryInput = Schema.Struct({
  /** Chosen by the client, so a retried add can't log twice. */
  id: Schema.optionalKey(DiaryEntryId),
  date: LocalDate,
  slot: MealSlot,
  /** Left out when logging a recipe: the recipe's title is used. */
  name: Schema.optionalKey(Name),
  amount: Schema.optionalKey(Amount),
  servings: Servings,
  /** Per serving. Left out when logging a recipe: the recipe's own are copied. */
  macros: Schema.optionalKey(MacrosInput),
  source: DiarySource,
  /** Required when `source` is `recipe`, and only then. */
  recipeId: Schema.optionalKey(Schema.NullOr(RecipeId)),
});
export type DiaryEntryInput = typeof DiaryEntryInput.Type;

export const DiaryBatchInput = Schema.Struct({
  entries: Schema.Array(DiaryEntryInput).check(
    Schema.isMinLength(1, { message: validation.required.text }),
    Schema.isMaxLength(TRACKER_LIMITS.batch, {
      message: validation.tooMany(TRACKER_LIMITS.batch).text,
    }),
  ),
});
export type DiaryBatchInput = typeof DiaryBatchInput.Type;

/** Change an entry's day, slot, servings, name, amount or numbers. */
export const DiaryEntryUpdate = Schema.Struct({
  date: Schema.optionalKey(LocalDate),
  slot: Schema.optionalKey(MealSlot),
  name: Schema.optionalKey(Name),
  amount: Schema.optionalKey(Amount),
  servings: Schema.optionalKey(Servings),
  macros: Schema.optionalKey(MacrosInput),
});
export type DiaryEntryUpdate = typeof DiaryEntryUpdate.Type;

/** One day as the tracker shows it. */
export const DiaryDayQuery = Schema.Struct({ date: LocalDate });
export type DiaryDayQuery = typeof DiaryDayQuery.Type;

/** A day range, both ends included. */
export const TrackerRangeQuery = Schema.Struct({ from: LocalDate, to: LocalDate });
export type TrackerRangeQuery = typeof TrackerRangeQuery.Type;

export const BodyProfile = Schema.Struct({
  sex: Sex,
  birthDate: LocalDate,
  heightCm: between(TRACKER_LIMITS.heightCm.min, TRACKER_LIMITS.heightCm.max),
  activity: ActivityLevel,
  goal: Goal,
  /** Kilograms a week; ignored when maintaining. */
  weeklyRateKg: between(TRACKER_LIMITS.weeklyRateKg.min, TRACKER_LIMITS.weeklyRateKg.max),
  /** Grams of protein per kilogram of bodyweight. */
  proteinPerKg: between(TRACKER_LIMITS.proteinPerKg.min, TRACKER_LIMITS.proteinPerKg.max),
  /** Share of calories from fat, 0.2 to 0.4. */
  fatShare: between(TRACKER_LIMITS.fatShare.min, TRACKER_LIMITS.fatShare.max),
  /** How weights and heights are shown. Everything is stored in metric. */
  weightUnit: WeightUnit,
  heightUnit: HeightUnit,
}).annotate({ identifier: "BodyProfile" });
export type BodyProfile = typeof BodyProfile.Type;

/** Which targets were typed in by hand rather than calculated. */
export const TargetOverrides = Schema.Struct({
  calories: Schema.Boolean,
  protein: Schema.Boolean,
  carbs: Schema.Boolean,
  fat: Schema.Boolean,
});
export type TargetOverrides = typeof TargetOverrides.Type;

export const TargetsInput = Schema.Struct({
  calories: wholeBetween(TRACKER_LIMITS.calories.min, TRACKER_LIMITS.calories.max),
  protein: wholeBetween(TRACKER_LIMITS.grams.min, TRACKER_LIMITS.grams.max),
  carbs: wholeBetween(TRACKER_LIMITS.grams.min, TRACKER_LIMITS.grams.max),
  fat: wholeBetween(TRACKER_LIMITS.grams.min, TRACKER_LIMITS.grams.max),
  overridden: TargetOverrides,
  /** The day of the last weekly check-in (#118); left out to keep the current one. */
  checkedInOn: Schema.optionalKey(Schema.NullOr(LocalDate)),
});
export type TargetsInput = typeof TargetsInput.Type;

export const Targets = Schema.Struct({
  calories: Schema.Int,
  protein: Schema.Int,
  carbs: Schema.Int,
  fat: Schema.Int,
  overridden: TargetOverrides,
  checkedInOn: Schema.NullOr(LocalDate),
}).annotate({ identifier: "Targets" });
export type Targets = typeof Targets.Type;

/** The profile and targets together; both null until the calculator has been run. */
export const TrackerSettings = Schema.Struct({
  profile: Schema.NullOr(BodyProfile),
  targets: Schema.NullOr(Targets),
}).annotate({ identifier: "TrackerSettings" });
export type TrackerSettings = typeof TrackerSettings.Type;

export const WeighIn = Schema.Struct({
  date: LocalDate,
  weightKg: Schema.Number,
}).annotate({ identifier: "WeighIn" });
export type WeighIn = typeof WeighIn.Type;

export const WeighInInput = Schema.Struct({
  weightKg: between(TRACKER_LIMITS.weightKg.min, TRACKER_LIMITS.weightKg.max),
});
export type WeighInInput = typeof WeighInInput.Type;

export const DiaryDay = Schema.Struct({
  date: LocalDate,
  /** By slot (breakfast to snack) and position. */
  entries: Schema.Array(DiaryEntry),
  totals: MacroTotals,
  targets: Schema.NullOr(Targets),
  weighIn: Schema.NullOr(WeighIn),
}).annotate({ identifier: "DiaryDay" });
export type DiaryDay = typeof DiaryDay.Type;

/** What one day added up to, for averages and the weekly check-in. */
export const IntakeDay = Schema.Struct({
  date: LocalDate,
  entries: Schema.Int,
  totals: MacroTotals,
}).annotate({ identifier: "IntakeDay" });
export type IntakeDay = typeof IntakeDay.Type;

/** What an entry adds to the day: its per-serving numbers times servings. */
export const entryTotals = (entry: Pick<DiaryEntry, "macros" | "servings">): MacroTotals => {
  const totals: MacroTotals = { calories: 0, protein: 0, carbs: 0, fat: 0 };
  for (const key of MACRO_KEYS) totals[key] = (entry.macros[key] ?? 0) * entry.servings;
  return totals;
};

/** The day's totals. Unknown values add nothing. */
export const dayTotals = (
  entries: ReadonlyArray<Pick<DiaryEntry, "macros" | "servings">>,
): MacroTotals => {
  const totals: MacroTotals = { calories: 0, protein: 0, carbs: 0, fat: 0 };
  for (const entry of entries) {
    const add = entryTotals(entry);
    for (const key of MACRO_KEYS) totals[key] += add[key];
  }
  return totals;
};

/** Whether an entry is missing any of its numbers. */
export const hasGaps = (entry: Pick<DiaryEntry, "macros">) =>
  MACRO_KEYS.some((key) => entry.macros[key] === null);

/** Describe it (#114): what was eaten, in words, for the model to split into foods. */
export const MEAL_DESCRIPTION_MAX = 1000;

export const MealDescription = Schema.Struct({
  text: Schema.Trim.check(
    Schema.isNonEmpty({ message: validation.required.text }),
    Schema.isMaxLength(MEAL_DESCRIPTION_MAX, {
      message: validation.tooLong(MEAL_DESCRIPTION_MAX).text,
    }),
  ),
});
export type MealDescription = typeof MealDescription.Type;

/**
 * One food the model found, with its amount and numbers for that amount.
 * Numbers are null when the model couldn't say, or the item isn't food.
 */
export const DescribedItem = Schema.Struct({
  name: Schema.String,
  amount: Schema.NullOr(Schema.String),
  macros: Macros,
}).annotate({ identifier: "DescribedItem" });
export type DescribedItem = typeof DescribedItem.Type;

export const MealEstimate = Schema.Struct({
  items: Schema.Array(DescribedItem),
}).annotate({ identifier: "MealEstimate" });
export type MealEstimate = typeof MealEstimate.Type;

/** Recents and favourites (#116): foods to log again in one tap. */
export const FavouriteId = Schema.String.check(Schema.isUUID()).pipe(Schema.brand("FavouriteId"));
export type FavouriteId = typeof FavouriteId.Type;

/** Something logged before, as it was last logged: what a one-tap re-log copies. */
export const QuickFood = Schema.Struct({
  name: Schema.String,
  amount: Schema.NullOr(Schema.String),
  /** Servings the last time it was logged. */
  servings: Schema.Number,
  /** Per serving. */
  macros: Macros,
  source: DiarySource,
  recipeId: Schema.NullOr(RecipeId),
}).annotate({ identifier: "QuickFood" });
export type QuickFood = typeof QuickFood.Type;

export const Favourite = Schema.Struct({
  id: FavouriteId,
  food: QuickFood,
}).annotate({ identifier: "Favourite" });
export type Favourite = typeof Favourite.Type;

export const RecentFood = Schema.Struct({
  food: QuickFood,
  /** Times logged in the recent window. */
  count: Schema.Int,
  lastLoggedOn: LocalDate,
  /** The latest entry it was logged as, for starring it. */
  lastEntryId: DiaryEntryId,
}).annotate({ identifier: "RecentFood" });
export type RecentFood = typeof RecentFood.Type;

export const QuickFoods = Schema.Struct({
  favourites: Schema.Array(Favourite),
  /** Most often logged first, then most recent. Starred foods are left out (they're above). */
  recents: Schema.Array(RecentFood),
}).annotate({ identifier: "QuickFoods" });
export type QuickFoods = typeof QuickFoods.Type;

/** Star a logged entry: it becomes a favourite as it was logged. */
export const FavouriteInput = Schema.Struct({ entryId: DiaryEntryId });
export type FavouriteInput = typeof FavouriteInput.Type;

/** Copy a day's entries (or one meal's) from `from` into `to`. */
export const DiaryCopyInput = Schema.Struct({
  from: LocalDate,
  to: LocalDate,
  /** Only this meal; the whole day when left out. */
  slot: Schema.optionalKey(Schema.NullOr(MealSlot)),
});
export type DiaryCopyInput = typeof DiaryCopyInput.Type;

/** The key recents and favourites are matched by: the recipe, or the name and amount. */
export const quickFoodKey = (food: Pick<QuickFood, "recipeId" | "name" | "amount">) =>
  food.recipeId !== null
    ? `recipe:${food.recipeId}`
    : `food:${food.name.trim().toLowerCase()}|${(food.amount ?? "").trim().toLowerCase()}`;
