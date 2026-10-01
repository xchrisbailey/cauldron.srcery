import { ingredientKey, parseIngredientLine } from "@cauldron/shared";
import { and, eq, sql } from "drizzle-orm";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import * as schema from "./schema/index.ts";
import { refreshRecipeSearch } from "./search.ts";
import { seedRecipes } from "./seed-recipes.ts";

type Db = PgDatabase<PgQueryResultHKT, typeof schema>;

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

    await db.transaction(async (tx) => {
      const [recipe] = await tx
        .insert(schema.recipe)
        .values({
          ownerId,
          title: r.title,
          description: r.description,
          servings: r.servings,
          prepMinutes: r.prepMinutes,
          cookMinutes: r.cookMinutes,
          totalMinutes: r.prepMinutes + r.cookMinutes,
          sourcePlatform: "manual",
          notes: r.notes ?? null,
        })
        .returning({ id: schema.recipe.id });
      const recipeId = recipe!.id;

      let section: string | null = null;
      let position = 0;
      const ingredients = [];
      for (const line of r.ingredients) {
        if (line.startsWith("## ")) {
          section = line.slice(3);
          continue;
        }
        const parsed = parseIngredientLine(line);
        ingredients.push({
          ownerId,
          recipeId,
          position: position++,
          section,
          quantityMin: parsed.quantity?.min ?? null,
          quantityMax: parsed.quantity?.max ?? null,
          unit: parsed.unit,
          item: parsed.item,
          itemKey: ingredientKey(parsed.item),
          note: parsed.note,
          optional: parsed.optional,
          altQuantityMin: parsed.alt?.quantity.min ?? null,
          altQuantityMax: parsed.alt?.quantity.max ?? null,
          altUnit: parsed.alt?.unit ?? null,
          originalLine: parsed.original,
        });
      }
      await tx.insert(schema.recipeIngredient).values(ingredients);

      await tx.insert(schema.recipeStep).values(
        r.steps.map((step, i) => ({
          ownerId,
          recipeId,
          position: i,
          text: step.text,
          timerSeconds: step.timerSeconds ?? null,
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
