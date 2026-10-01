import { parseIngredientLine, RecipeInput } from "@cauldron/shared";
import { and, eq, isNull, sql } from "drizzle-orm";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import { Schema } from "effect";
import { ingredient } from "./codec.ts";
import * as schema from "./schema/index.ts";
import { refreshRecipeSearch } from "./search.ts";

type Db = PgDatabase<PgQueryResultHKT, typeof schema>;

const decodeRecipe = Schema.decodeUnknownSync(RecipeInput);

const BATCH_SIZE = 50;
const DAY_MS = 86_400_000;

// mulberry32: a small deterministic PRNG, so every run generates the same recipes.
const makeRng = (seed: number) => {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};

const adjectives = [
  "Smoky",
  "Lemony",
  "Crispy",
  "Creamy",
  "Spicy",
  "Roasted",
  "Garlicky",
  "Herby",
  "Sticky",
  "Slow-cooked",
  "Charred",
  "Buttery",
  "Zesty",
  "Hearty",
  "Sunday",
  "Weeknight",
];
const mains = [
  "chickpea",
  "orzo",
  "salmon",
  "chicken",
  "mushroom",
  "lentil",
  "sweet potato",
  "pork",
  "tofu",
  "cauliflower",
  "beef",
  "prawn",
  "aubergine",
  "white bean",
  "courgette",
  "turkey",
];
const dishes = [
  "stew",
  "salad",
  "curry",
  "pasta",
  "traybake",
  "soup",
  "tacos",
  "bowls",
  "skillet",
  "bake",
  "stir-fry",
  "flatbreads",
  "risotto",
  "noodles",
];

const ingredientLines = [
  "2 tbsp olive oil",
  "1 tbsp butter",
  "1 large onion, finely chopped",
  "2 shallots, sliced",
  "3 cloves garlic, minced",
  "1 inch fresh ginger, grated",
  "1 tsp ground cumin",
  "1 tsp smoked paprika",
  "1/2 tsp chilli flakes",
  "1 tsp dried oregano",
  "1 tsp kosher salt",
  "1/2 tsp black pepper",
  "1 (14 oz) can chopped tomatoes",
  "1 (15 oz) can chickpeas, drained",
  "400 g cherry tomatoes, halved",
  "2 cups chicken stock",
  "1 cup vegetable stock",
  "1/2 cup dry white wine",
  "200 g orzo",
  "250 g spaghetti",
  "1 1/2 cups basmati rice",
  "2 carrots, diced",
  "2 stalks celery, diced",
  "1 red bell pepper, sliced",
  "1 zucchini, cubed",
  "200 g baby spinach",
  "1 lb chicken thighs",
  "500 g salmon fillets",
  "300 g firm tofu, pressed",
  "1/2 cup plain yogurt",
  "1/4 cup heavy cream",
  "1/2 cup grated parmesan",
  "100 g feta, crumbled",
  "juice of 1 lemon",
  "zest of 1 lemon",
  "1 lime, cut into wedges",
  "1/4 cup chopped fresh parsley",
  "2 tbsp chopped fresh cilantro",
  "a handful of fresh basil",
  "1 tbsp soy sauce",
  "1 tbsp honey",
  "2 tsp red wine vinegar",
  "1 tbsp tomato paste",
  "1/4 cup toasted pine nuts",
  "2 tbsp tahini",
  "4 flour tortillas",
  "1 ripe avocado, sliced",
  "1 tbsp cornstarch",
  "1 tsp lemon juice (optional)",
  "salt and pepper",
];

// Steps; `{n}` is replaced with the minutes, and a step with minutes gets a timer.
const stepTemplates: ReadonlyArray<{ text: string; timed: boolean }> = [
  { text: "Heat the oil in a large pan over medium heat.", timed: false },
  { text: "Cook the onion and garlic for {n} minutes until soft.", timed: true },
  { text: "Stir in the spices and cook for 1 minute until fragrant.", timed: false },
  { text: "Add the remaining ingredients and bring to a simmer.", timed: false },
  { text: "Simmer gently for {n} minutes, stirring now and then.", timed: true },
  { text: "Roast on a lined tray for {n} minutes until golden.", timed: true },
  { text: "Rest for {n} minutes before serving.", timed: true },
  { text: "Taste and adjust the seasoning.", timed: false },
  { text: "Toss everything together and serve warm.", timed: false },
  { text: "Scatter over the fresh herbs and serve.", timed: false },
];

type TagKind = "cuisine" | "meal" | "diet" | "other";
const tagSet: ReadonlyArray<{ name: string; kind: TagKind }> = [
  { name: "Italian", kind: "cuisine" },
  { name: "Mexican", kind: "cuisine" },
  { name: "Indian", kind: "cuisine" },
  { name: "Middle Eastern", kind: "cuisine" },
  { name: "Dinner", kind: "meal" },
  { name: "Lunch", kind: "meal" },
  { name: "Breakfast", kind: "meal" },
  { name: "Vegetarian", kind: "diet" },
  { name: "Vegan", kind: "diet" },
  { name: "Quick", kind: "other" },
  { name: "Weeknight", kind: "other" },
  { name: "Meal prep", kind: "other" },
];

/**
 * Tops `ownerId` up to `count` live recipes with generated ones, for load and
 * search-as-you-type checks. Deterministic, and idempotent: it counts the
 * owner's existing live recipes and only adds the difference.
 */
export const seedMany = async (db: Db, ownerId: string, count: number) => {
  const [existing] = await db
    .select({ n: sql<number>`count(*)::int` })
    .from(schema.recipe)
    .where(and(eq(schema.recipe.ownerId, ownerId), isNull(schema.recipe.deletedAt)));
  const existingCount = existing!.n;
  const toCreate = Math.max(0, count - existingCount);
  if (toCreate === 0) return { created: 0, total: existingCount };

  // Offset the stream by what already exists, so a top-up differs from the first run.
  const rng = makeRng(0xca1d + existingCount);
  const int = (min: number, max: number) => min + Math.floor(rng() * (max - min + 1));
  const pick = <T>(xs: ReadonlyArray<T>): T => xs[Math.floor(rng() * xs.length)]!;
  const sample = <T>(xs: ReadonlyArray<T>, n: number): Array<T> => {
    const pool = [...xs];
    const out: Array<T> = [];
    while (out.length < n && pool.length > 0)
      out.push(pool.splice(Math.floor(rng() * pool.length), 1)[0]!);
    return out;
  };

  // Tags are reused case-insensitively, like `seed()` does.
  const tagIds = new Map<string, string>();
  for (const t of await db
    .select({ id: schema.tag.id, name: schema.tag.name })
    .from(schema.tag)
    .where(eq(schema.tag.ownerId, ownerId))) {
    tagIds.set(t.name.toLowerCase(), t.id);
  }
  for (const t of tagSet) {
    if (tagIds.has(t.name.toLowerCase())) continue;
    const [row] = await db
      .insert(schema.tag)
      .values({ ownerId, name: t.name, kind: t.kind })
      .returning({ id: schema.tag.id });
    tagIds.set(t.name.toLowerCase(), row!.id);
  }

  const now = Date.now();
  for (let done = 0; done < toCreate; done += BATCH_SIZE) {
    const size = Math.min(BATCH_SIZE, toCreate - done);
    const recipes: Array<typeof schema.recipe.$inferInsert> = [];
    const generated = Array.from({ length: size }, () => {
      const prep = int(5, 30);
      const cook = int(10, 90);
      const createdAt = new Date(now - Math.floor(rng() * 365 * DAY_MS));
      const lastCooked =
        rng() < 0.4
          ? new Date(createdAt.getTime() + Math.floor(rng() * (now - createdAt.getTime())))
          : null;
      const title = `${pick(adjectives)} ${pick(mains)} ${pick(dishes)}`;
      // Built as the API would receive it, and validated the same way.
      const input = decodeRecipe({
        title,
        description: `A ${title.toLowerCase()} for an easy evening.`,
        servings: int(2, 8),
        prepMinutes: prep,
        cookMinutes: cook,
        totalMinutes: prep + cook,
        sourcePlatform: "manual",
        sourceUrl: null,
        sourceAuthor: null,
        notes: null,
        photoKey: null,
        ingredients: sample(ingredientLines, int(5, 12)).map((line) => ({
          section: null,
          ...parseIngredientLine(line),
        })),
        steps: sample(stepTemplates, int(3, 6)).map((t) => {
          const minutes = int(2, 45);
          return {
            section: null,
            text: t.text.replace("{n}", String(minutes)),
            timerSeconds: t.timed ? minutes * 60 : null,
          };
        }),
        tags: sample(tagSet, int(1, 3)).map((t) => t.name),
      });
      recipes.push({
        ownerId,
        title: input.title,
        description: input.description,
        servings: input.servings,
        prepMinutes: input.prepMinutes,
        cookMinutes: input.cookMinutes,
        totalMinutes: input.totalMinutes,
        sourcePlatform: input.sourcePlatform,
        createdAt,
        updatedAt: createdAt,
        lastCookedOn: lastCooked ? lastCooked.toISOString().slice(0, 10) : null,
      });
      return input;
    });

    await db.transaction(async (tx) => {
      const rows = await tx
        .insert(schema.recipe)
        .values(recipes)
        .returning({ id: schema.recipe.id });
      const ingredientRows: Array<typeof schema.recipeIngredient.$inferInsert> = [];
      const stepRows: Array<typeof schema.recipeStep.$inferInsert> = [];
      const tagRows: Array<typeof schema.recipeTag.$inferInsert> = [];
      generated.forEach((g, i) => {
        const recipeId = rows[i]!.id;
        g.ingredients.forEach((line, position) =>
          ingredientRows.push({ ownerId, recipeId, position, ...ingredient.toRow(line) }),
        );
        g.steps.forEach((s, position) =>
          stepRows.push({
            ownerId,
            recipeId,
            position,
            text: s.text,
            timerSeconds: s.timerSeconds,
          }),
        );
        for (const name of g.tags) {
          tagRows.push({ ownerId, recipeId, tagId: tagIds.get(name.toLowerCase())! });
        }
      });
      await tx.insert(schema.recipeIngredient).values(ingredientRows);
      await tx.insert(schema.recipeStep).values(stepRows);
      await tx.insert(schema.recipeTag).values(tagRows);
      await tx.execute(
        refreshRecipeSearch(
          ownerId,
          rows.map((r) => r.id),
        ),
      );
    });
  }
  return { created: toCreate, total: count };
};
