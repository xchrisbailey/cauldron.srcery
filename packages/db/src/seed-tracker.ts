import { addDays, calculateTargets, type MealSlot } from "@cauldron/shared";
import { and, eq, lt } from "drizzle-orm";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import * as schema from "./schema/index.ts";

// Four weeks of tracker history for the demo account (#23): a body profile and
// targets, weigh-ins drifting down with day-to-day noise, and most days'
// meals logged, so the diary, the weight trend and the weekly check-in all
// have something to show. Deterministic, and skipped once the account has
// weigh-ins before today.

type Db = PgDatabase<PgQueryResultHKT, typeof schema>;

const DAYS = 28;

const PROFILE = {
  sex: "female",
  birthDate: "1990-05-14",
  heightCm: 168,
  activity: "light",
  goal: "lose",
  weeklyRateKg: 0.5,
  proteinPerKg: 1.8,
  fatShare: 0.25,
  weightUnit: "kg",
  heightUnit: "cm",
} as const;

type Food = readonly [
  name: string,
  amount: string,
  calories: number,
  protein: number,
  carbs: number,
  fat: number,
];

const MEALS: Record<MealSlot, ReadonlyArray<ReadonlyArray<Food>>> = {
  breakfast: [
    [["Overnight oats", "1 jar", 380, 14, 58, 10]],
    [
      ["Greek yogurt", "200 g", 190, 20, 8, 9],
      ["Blueberries", "1 handful", 40, 0.5, 10, 0],
    ],
    [
      ["Eggs", "2 large", 143, 12.5, 1, 9.5],
      ["Sourdough toast", "1 slice", 100, 4, 19, 1],
    ],
  ],
  lunch: [
    [["Tomato and white bean soup", "1 bowl", 260, 12, 38, 6]],
    [["Chicken salad wrap", "1 wrap", 450, 32, 40, 16]],
    [["Leftover dal with rice", "1 bowl", 520, 20, 82, 11]],
  ],
  dinner: [
    [["Weeknight chicken thighs", "1 serving", 540, 42, 12, 34]],
    [["Shakshuka with feta", "1 serving", 310, 18, 16, 19]],
    [
      ["Salmon", "1 fillet", 360, 34, 0, 23],
      ["Roast potatoes", "1 cup", 210, 4, 32, 8],
    ],
  ],
  snack: [
    [["Apple", "1 medium", 95, 0.5, 25, 0.3]],
    [["Dark chocolate", "2 squares", 110, 1.5, 9, 8]],
    [["Almonds", "1 handful", 160, 6, 6, 14]],
  ],
};

/** A small deterministic generator, so every seed gives the same history. */
const random = (seed: number) => () => {
  seed = (seed * 1_103_515_245 + 12_345) % 2_147_483_648;
  return seed / 2_147_483_648;
};

const localToday = () => {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
};

/** Seeds the tracker history for `ownerId`. Returns how many days were filled, or 0 if skipped. */
export const seedTracker = async (db: Db, ownerId: string, today = localToday()) => {
  const existing = await db
    .select({ date: schema.weighIn.date })
    .from(schema.weighIn)
    .where(and(eq(schema.weighIn.ownerId, ownerId), lt(schema.weighIn.date, today)))
    .limit(1);
  if (existing.length > 0) return 0;

  const next = random(23);
  const start = addDays(today, -DAYS);
  const startKg = 74.2;
  const weighIns: Array<typeof schema.weighIn.$inferInsert> = [];
  const entries: Array<typeof schema.diaryEntry.$inferInsert> = [];
  for (let i = 0; i < DAYS; i++) {
    const date = addDays(start, i);
    // About 0.45 kg a week down, with a kilo of water noise either way.
    if (next() < 0.85) {
      const weightKg = startKg - (0.45 / 7) * i + (next() - 0.5) * 1.2;
      weighIns.push({ ownerId, date, weightKg: Math.round(weightKg * 100) / 100 });
    }
    // Most days are logged; some are forgotten.
    if (next() < 0.2) continue;
    for (const slot of ["breakfast", "lunch", "dinner", "snack"] as const) {
      if (slot === "snack" && next() < 0.2) continue;
      const options = MEALS[slot];
      const meal = options[Math.floor(next() * options.length)]!;
      meal.forEach(([name, amount, calories, protein, carbs, fat], position) =>
        entries.push({
          ownerId,
          date,
          slot,
          name,
          amount,
          // Bigger plates at lunch and dinner, so the days land near maintenance.
          servings: slot === "lunch" || slot === "dinner" ? 1.5 : 1,
          calories,
          proteinGrams: protein,
          carbsGrams: carbs,
          fatGrams: fat,
          source: "described",
          position,
        }),
      );
    }
  }

  await db.transaction(async (tx) => {
    const [profile] = await tx
      .select({ ownerId: schema.bodyProfile.ownerId })
      .from(schema.bodyProfile)
      .where(eq(schema.bodyProfile.ownerId, ownerId));
    if (!profile) await tx.insert(schema.bodyProfile).values({ ownerId, ...PROFILE });
    const [targets] = await tx
      .select({ ownerId: schema.trackerTargets.ownerId })
      .from(schema.trackerTargets)
      .where(eq(schema.trackerTargets.ownerId, ownerId));
    if (!targets) {
      const { targets: t } = calculateTargets({ ...PROFILE, weightKg: startKg, today: start });
      // Last checked in over a week ago, so the weekly check-in is due.
      await tx
        .insert(schema.trackerTargets)
        .values({ ownerId, ...t, checkedInOn: addDays(today, -8) });
    }
    if (weighIns.length > 0) await tx.insert(schema.weighIn).values(weighIns);
    if (entries.length > 0) await tx.insert(schema.diaryEntry).values(entries);
  });
  return DAYS;
};
