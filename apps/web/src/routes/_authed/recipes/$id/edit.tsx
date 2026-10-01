import * as stylex from "@stylexjs/stylex";
import { copy, type Recipe } from "@cauldron/shared";
import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { RecipeEditor } from "../../../../components/editor/RecipeEditor";
import { ButtonLink, EmptyState, PageHeader, Skeleton } from "../../../../components/ui";
import { failureOf } from "../../../../lib/api-failure";
import { decodeRecipeForm, fromRecipe, type RecipeFormValues } from "../../../../lib/recipe-form";
import { recipeQuery } from "../../../../lib/recipes";
import { useRecipeWrites } from "../../../../lib/use-recipe-writes";

export const Route = createFileRoute("/_authed/recipes/$id/edit")({ component: Edit });

const isNotFound = (error: unknown) => failureOf(error).tag === "NotFound";

function Edit() {
  const { id } = Route.useParams();
  const recipe = useQuery(recipeQuery(id));

  if (recipe.isPending) {
    return (
      <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.rows)}>
        <Skeleton height={40} />
        <Skeleton width="60%" />
        <Skeleton width="80%" />
      </div>
    );
  }
  if (recipe.isError) {
    return (
      <>
        <PageHeader title={copy.editor.editTitle.text} />
        <EmptyState
          message={isNotFound(recipe.error) ? copy.errors.notFound.text : copy.errors.internal.text}
        />
      </>
    );
  }
  // Keyed by id so moving between recipes starts a fresh form.
  return <Editor key={id} id={id} recipe={recipe.data} />;
}

function Editor({ id, recipe }: { id: string; recipe: Recipe }) {
  const writes = useRecipeWrites();
  // Read once: a background refetch mustn't reset a form being edited.
  const [initial] = useState(() => fromRecipe(recipe));

  const save = async (values: RecipeFormValues) => {
    const input = decodeRecipeForm(values);
    if (!input) return "invalid" as const;
    try {
      await writes.update(id, input);
      return "saved" as const;
    } catch {
      // The status line says so; a toast every few seconds offline is noise.
      return "error" as const;
    }
  };

  return (
    <RecipeEditor
      title={copy.editor.editTitle.text}
      initial={initial}
      keep={{ save }}
      actions={() => (
        <ButtonLink to="/recipes/$id" params={{ id }} variant="secondary">
          {copy.editor.done.text}
        </ButtonLink>
      )}
    />
  );
}

const styles = stylex.create({ rows: { display: "grid", gap: 12, maxWidth: 560 } });
