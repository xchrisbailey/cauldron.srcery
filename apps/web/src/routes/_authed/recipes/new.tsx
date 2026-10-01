import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { RecipeEditor } from "../../../components/editor/RecipeEditor";
import { Button, Dialog, Skeleton, useToast } from "../../../components/ui";
import { loadDraft } from "../../../lib/recipe-draft";
import { decodeRecipeForm, emptyRecipeForm, type RecipeFormValues } from "../../../lib/recipe-form";
import { useRecipeWrites } from "../../../lib/use-recipe-writes";
import { colors } from "../../../styles/tokens.stylex";

export const Route = createFileRoute("/_authed/recipes/new")({ component: Conjure });

// A new recipe is kept as a draft in this browser while it's written, and only
// reaches the API on Save. Imports (#13) will open this editor prefilled.
function Conjure() {
  const navigate = useNavigate();
  const writes = useRecipeWrites();
  const toast = useToast();
  // The draft lives in this browser, so it's read after hydration.
  const [initial, setInitial] = useState<RecipeFormValues | null>(null);
  const [generation, setGeneration] = useState(0);
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

  // A finished draft (saved or cleared) is discarded, so the editor's flush
  // on the way out can't write it back.
  const onSubmit = async (values: RecipeFormValues, { discard }: { discard: () => void }) => {
    const input = decodeRecipeForm(values);
    if (!input) return;
    try {
      const recipe = await writes.create(input);
      discard();
      await navigate({ to: "/recipes/$id", params: { id: recipe.id }, replace: true });
    } catch {
      toast(copy.editor.couldntSave.text, "error");
    }
  };

  return (
    <RecipeEditor
      key={generation}
      title={copy.editor.newTitle.text}
      initial={initial}
      keep="draft"
      onSubmit={onSubmit}
      actions={({ submit, submitting, discard }) => (
        <>
          <StartOver
            onConfirm={() => {
              discard();
              setInitial(emptyRecipeForm());
              setGeneration((n) => n + 1);
            }}
          />
          <Button onClick={submit} disabled={submitting}>
            {copy.editor.save.text}
          </Button>
        </>
      )}
    />
  );
}

function StartOver({ onConfirm }: { onConfirm: () => void }) {
  const [confirming, setConfirming] = useState(false);
  return (
    <>
      <Button variant="ghost" onClick={() => setConfirming(true)}>
        {copy.editor.startOver.text}
      </Button>
      <Dialog
        open={confirming}
        onClose={() => setConfirming(false)}
        title={copy.editor.startOver.text}
      >
        <p {...stylex.props(styles.body)}>{copy.editor.startOverConfirm.text}</p>
        <div {...stylex.props(styles.actions)}>
          <Button variant="secondary" data-autofocus onClick={() => setConfirming(false)}>
            {copy.editor.stay.text}
          </Button>
          <Button
            variant="danger"
            onClick={() => {
              setConfirming(false);
              onConfirm();
            }}
          >
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
