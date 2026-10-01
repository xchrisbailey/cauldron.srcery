import { readIngredientBlock, RecipeInput } from "@cauldron/shared";
import { and, eq, sql } from "drizzle-orm";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import { Schema } from "effect";
import { ingredient, macros } from "./codec.ts";
import * as schema from "./schema/index.ts";
import { refreshRecipeSearch } from "./search.ts";
import { type SeedRecipe, seedRecipes } from "./seed-recipes.ts";

type Db = PgDatabase<PgQueryResultHKT, typeof schema>;

const decodeRecipe = Schema.decodeUnknownSync(RecipeInput);

/** A seed recipe as the API would receive it. Throws if it isn't valid input. */
const toInput = (r: SeedRecipe): RecipeInput =>
  decodeRecipe({
    title: r.title,
    description: r.description,
    servings: r.servings,
    prepMinutes: r.prepMinutes,
    cookMinutes: r.cookMinutes,
    totalMinutes: r.prepMinutes + r.cookMinutes,
    sourcePlatform: "manual",
    sourceUrl: null,
    sourceAuthor: null,
    notes: r.notes ?? null,
    photoKey: null,
    ...(r.macros === undefined ? {} : { macros: r.macros }),
    tags: r.tags.map((t) => t.name),
    ingredients: readIngredientBlock(r.ingredients),
    steps: r.steps.map((step) => ({
      section: null,
      text: step.text,
      timerSeconds: step.timerSeconds ?? null,
    })),
  });

/**
 * Loads the seed recipes for `ownerId`. Idempotent: recipes the owner already
 * has with the same title are skipped.
 */
export const seed = async (db: Db, ownerId: string) => {
  let created = 0;
  for (const r of seedRecipes) {
    const existing = await db
      .select({ id: schema.recipe.id })
      .from(schema.recipe)
      .where(and(eq(schema.recipe.ownerId, ownerId), eq(schema.recipe.title, r.title)))
      .limit(1);
    if (existing.length > 0) continue;
    const input = toInput(r);

    await db.transaction(async (tx) => {
      const [recipe] = await tx
        .insert(schema.recipe)
        .values({
          ownerId,
          title: input.title,
          description: input.description,
          servings: input.servings,
          prepMinutes: input.prepMinutes,
          cookMinutes: input.cookMinutes,
          totalMinutes: input.totalMinutes,
          ...(input.macros === undefined ? {} : macros.toRow(input.macros)),
          sourcePlatform: input.sourcePlatform,
          notes: input.notes,
        })
        .returning({ id: schema.recipe.id });
      const recipeId = recipe!.id;

      await tx.insert(schema.recipeIngredient).values(
        input.ingredients.map((line, position) => ({
          ownerId,
          recipeId,
          position,
          ...ingredient.toRow(line),
        })),
      );

      await tx.insert(schema.recipeStep).values(
        input.steps.map((step, i) => ({
          ownerId,
          recipeId,
          position: i,
          text: step.text,
          timerSeconds: step.timerSeconds,
        })),
      );

      for (const t of r.tags) {
        const [existingTag] = await tx
          .select({ id: schema.tag.id })
          .from(schema.tag)
          .where(
            and(eq(schema.tag.ownerId, ownerId), sql`lower(${schema.tag.name}) = lower(${t.name})`),
          );
        const tagId =
          existingTag?.id ??
          (
            await tx
              .insert(schema.tag)
              .values({ ownerId, name: t.name, kind: t.kind })
              .returning({ id: schema.tag.id })
          )[0]!.id;
        await tx.insert(schema.recipeTag).values({ ownerId, recipeId, tagId });
      }
      await tx.execute(refreshRecipeSearch(ownerId, [recipeId]));
    });
    created++;
  }
  return { created, total: seedRecipes.length };
};
