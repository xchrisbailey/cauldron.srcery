import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { useQueryClient } from "@tanstack/react-query";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { RecipeEditor, snapshotOf } from "../../../components/editor/RecipeEditor";
import { Button, Dialog, Skeleton, useToast } from "../../../components/ui";
import { clearDraft, loadDraft, saveDraft } from "../../../lib/recipe-draft";
import { decodeRecipeForm, emptyRecipeForm, type RecipeFormValues } from "../../../lib/recipe-form";
import { createRecipe, settleRecipe } from "../../../lib/recipes";
import { colors } from "../../../styles/tokens.stylex";

export const Route = createFileRoute("/_authed/recipes/new")({ component: Conjure });

const EMPTY = snapshotOf(emptyRecipeForm());

// A new recipe is kept as a draft in this browser while it's written, and only
// reaches the API on Save. Imports (#13) will open this editor prefilled.
function Conjure() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const toast = useToast();
  // The draft lives in this browser, so it's read after hydration.
  const [initial, setInitial] = useState<RecipeFormValues | null>(null);
  const [generation, setGeneration] = useState(0);
  const [confirmingReset, setConfirmingReset] = useState(false);
  // Bumped when this draft is finished (saved or cleared), so the editor's
  // flush on the way out can't write it back.
  const draftGeneration = useRef(0);
  useEffect(() => setInitial(loadDraft() ?? emptyRecipeForm()), []);

  if (!initial) {
    return (
      <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.loading)}>
        <Skeleton height={40} />
        <Skeleton width="60%" />
        <Skeleton width="80%" />
      </div>
    );
  }

  const draftAtRender = draftGeneration.current;
  const persist = async (values: RecipeFormValues) => {
    if (draftAtRender !== draftGeneration.current) return "idle" as const;
    if (snapshotOf(values) === EMPTY) {
      clearDraft();
      return "idle" as const;
    }
    return saveDraft(values) ? ("kept" as const) : ("idle" as const);
  };

  const onSubmit = async (values: RecipeFormValues) => {
    const input = decodeRecipeForm(values);
    if (!input) return;
    try {
      const recipe = await createRecipe(input);
      draftGeneration.current++;
      clearDraft();
      settleRecipe(queryClient, recipe);
      await navigate({ to: "/recipes/$id/edit", params: { id: recipe.id }, replace: true });
    } catch {
      toast(copy.editor.couldntSave.text, "error");
    }
  };

  const startOver = () => {
    draftGeneration.current++;
    clearDraft();
    setInitial(emptyRecipeForm());
    setGeneration((n) => n + 1);
    setConfirmingReset(false);
  };

  return (
    <>
      <RecipeEditor
        key={generation}
        title={copy.editor.newTitle.text}
        initial={initial}
        persisted={snapshotOf(initial)}
        persist={persist}
        onSubmit={onSubmit}
        guard={false}
        actions={({ submit, submitting }) => (
          <>
            <Button variant="ghost" onClick={() => setConfirmingReset(true)}>
              {copy.editor.startOver.text}
            </Button>
            <Button onClick={submit} disabled={submitting}>
              {copy.editor.save.text}
            </Button>
          </>
        )}
      />
      <Dialog
        open={confirmingReset}
        onClose={() => setConfirmingReset(false)}
        title={copy.editor.startOver.text}
      >
        <p {...stylex.props(styles.body)}>{copy.editor.startOverConfirm.text}</p>
        <div {...stylex.props(styles.actions)}>
          <Button variant="secondary" data-autofocus onClick={() => setConfirmingReset(false)}>
            {copy.editor.stay.text}
          </Button>
          <Button variant="danger" onClick={startOver}>
            {copy.editor.startOver.text}
          </Button>
        </div>
      </Dialog>
    </>
  );
}

const styles = stylex.create({
  loading: { display: "grid", gap: 12, maxWidth: 560 },
  body: { margin: 0, color: colors.subtext },
  actions: { display: "flex", flexWrap: "wrap", gap: 8 },
});
