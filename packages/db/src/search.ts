import { inArray, sql, type SQL } from "drizzle-orm";
import { recipe } from "./schema/recipes.ts";

/**
 * Recomputes `recipe.search` for the given recipes from their title, tags,
 * ingredient items and description (the `recipe_search_document` SQL
 * function from migration 0002). Run it after writing any of those.
 */
export const refreshRecipeSearch = (recipeIds: ReadonlyArray<string>): SQL =>
  sql`update ${recipe} set search = recipe_search_document(${recipe.id}) where ${inArray(recipe.id, [...recipeIds])}`;
