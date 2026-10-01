import * as stylex from "@stylexjs/stylex";
import { copy, type Recipe } from "@cauldron/shared";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { RecipeEditor, snapshotOf } from "../../../../components/editor/RecipeEditor";
import { ButtonLink, EmptyState, PageHeader, Skeleton } from "../../../../components/ui";
import { decodeRecipeForm, fromRecipe, type RecipeFormValues } from "../../../../lib/recipe-form";
import { recipeQuery, settleRecipe, updateRecipe } from "../../../../lib/recipes";

export const Route = createFileRoute("/_authed/recipes/$id/edit")({ component: Edit });

const isNotFound = (error: unknown) =>
  typeof error === "object" && error !== null && "_tag" in error && error._tag === "NotFound";

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
  const queryClient = useQueryClient();
  // Read once: a background refetch mustn't reset a form being edited.
  const [initial] = useState(() => fromRecipe(recipe));
  const persisted = useMemo(() => snapshotOf(initial), [initial]);

  const persist = async (values: RecipeFormValues) => {
    const input = decodeRecipeForm(values);
    if (!input) return "invalid" as const;
    try {
      settleRecipe(queryClient, await updateRecipe(id, input));
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
      persisted={persisted}
      persist={persist}
      guard
      actions={() => (
        <ButtonLink to="/recipes/$id" params={{ id }} variant="secondary">
          {copy.editor.done.text}
        </ButtonLink>
      )}
    />
  );
}

const styles = stylex.create({ rows: { display: "grid", gap: 12, maxWidth: 560 } });
