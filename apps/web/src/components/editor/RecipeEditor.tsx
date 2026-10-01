import * as stylex from "@stylexjs/stylex";
import { copy, MACRO_KEYS, RECIPE_LIMITS } from "@cauldron/shared";
import { useForm, useStore } from "@tanstack/react-form";
import { useDebouncer } from "@tanstack/react-pacer";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useBlocker } from "@tanstack/react-router";
import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import {
  type RecipeFormValues,
  type ReviewField,
  toRecipeInput,
  validateRecipeForm,
} from "../../lib/recipe-form";
import { estimateMacros, tagsQuery } from "../../lib/recipes";
import { colors, fonts, type } from "../../styles/tokens.stylex";
import { Button, Dialog, FormMessage, Input, PageHeader, Textarea } from "../ui";
import { IngredientRows } from "./IngredientRows";
import { PhotoField } from "./PhotoField";
import { StepRows } from "./StepRows";
import { TagInput } from "./TagInput";

// The recipe editor, shared by Conjure (a new recipe) and Edit. Every change
// is kept as it happens: a new recipe as a draft in this browser until it's
// saved, an existing one straight to the API. Both are debounced with Pacer.

export type SaveStatus = "idle" | "pending" | "saving" | "saved" | "kept" | "invalid" | "error";

/**
 * What the form says, compared without row keys. The number fields go in as
 * typed, so "ten" differs from a blank field even though neither is a number.
 */
export const snapshotOf = (values: RecipeFormValues) =>
  JSON.stringify([
    toRecipeInput(values).input,
    values.servings,
    values.prepMinutes,
    values.cookMinutes,
    values.totalMinutes,
    values.macros,
  ]);

interface Props {
  title: string;
  initial: RecipeFormValues;
  /** Called (debounced) with each change; resolves to the status to show. */
  persist: (values: RecipeFormValues) => Promise<SaveStatus>;
  /** The snapshot already persisted, so an unchanged form isn't saved again. */
  persisted: string;
  /** Header actions beside the save status, e.g. Save or Done. */
  actions: (form: { submit: () => void; submitting: boolean }) => ReactNode;
  /** Runs on Save with the validated input. */
  onSubmit?: (values: RecipeFormValues) => Promise<void>;
  /** Hold navigation while changes are unsaved (existing recipes). */
  guard: boolean;
  /** Shown under the header, before the fields: an import's source and notes. */
  intro?: ReactNode;
}

export function RecipeEditor({
  title,
  initial,
  persist,
  persisted,
  actions,
  onSubmit,
  guard,
  intro,
}: Props) {
  const [status, setStatus] = useState<SaveStatus>("idle");
  const [showAllErrors, setShowAllErrors] = useState(false);
  const [touched, setTouched] = useState<ReadonlySet<string>>(new Set());
  const saved = useRef(persisted);
  const queue = useRef<Promise<unknown>>(Promise.resolve());
  const tags = useQuery(tagsQuery());

  const form = useForm({
    defaultValues: initial,
    validators: {
      // A form-level error only: the editor shows field errors itself, and
      // field errors set here would never clear without registered fields.
      onSubmit: ({ value }) =>
        Object.keys(validateRecipeForm(value)).length > 0 ? copy.editor.fixErrors.text : undefined,
    },
    onSubmit: async ({ value }) => {
      if (onSubmit) await onSubmit(value);
    },
  });

  const values = useStore(form.store, (state) => state.values);
  const submitting = useStore(form.store, (state) => state.isSubmitting);
  const submitted = useStore(form.store, (state) => state.submissionAttempts > 0);
  const errors = useMemo(() => validateRecipeForm(values), [values]);
  const snapshot = useMemo(() => snapshotOf(values), [values]);
  const latest = useRef(snapshot);
  latest.current = snapshot;
  const latestValues = useRef(values);
  latestValues.current = values;
  /** The status of the last save that finished, shown again when the form matches it. */
  const settled = useRef<SaveStatus>("idle");

  // Saves run one at a time, in order, so an older save never lands last. If
  // the form changed while one was running, the newest values go next.
  const save = (next: RecipeFormValues) => {
    const run = queue.current.then(async () => {
      const shot = snapshotOf(next);
      if (shot !== saved.current) {
        setStatus("saving");
        const result = await persist(next);
        if (result === "saved" || result === "kept") saved.current = shot;
        if (result === "invalid") setShowAllErrors(true);
        settled.current = result;
      }
      if (latest.current === saved.current) setStatus(settled.current);
      else if (latest.current !== shot) debouncer.maybeExecute(latestValues.current);
      else setStatus(settled.current);
    });
    queue.current = run.catch(() => undefined);
    return run;
  };

  // Unmounting flushes rather than cancels, so the last change is kept.
  const debouncer = useDebouncer(save, { wait: 800, onUnmount: (d) => d.flush() });

  useEffect(() => {
    if (snapshot === saved.current) {
      // Back to what's saved (an edit undone): nothing to send.
      debouncer.cancel();
      setStatus(settled.current);
      return;
    }
    setStatus("pending");
    debouncer.maybeExecute(values);
    // The debouncer is stable; only new text should schedule a save.
  }, [snapshot]);

  // Closing or reloading the tab keeps the last change too.
  useEffect(() => {
    const flush = () => debouncer.flush();
    window.addEventListener("pagehide", flush);
    return () => window.removeEventListener("pagehide", flush);
  }, [debouncer]);

  const blocker = useBlocker({
    shouldBlockFn: async () => {
      if (!guard || latest.current === saved.current) return false;
      debouncer.flush();
      await queue.current;
      return latest.current !== saved.current;
    },
    enableBeforeUnload: () => guard && latest.current !== saved.current,
    withResolver: true,
  });

  // After a failed save, take the cook to the first field that needs a fix.
  const submit = async () => {
    await form.handleSubmit();
    if (Object.keys(validateRecipeForm(form.state.values)).length > 0) {
      // After React has rendered the error states.
      setTimeout(
        () => document.querySelector<HTMLElement>("form [aria-invalid='true']")?.focus(),
        50,
      );
    }
  };

  const review = new Set(values.review);
  const setField = <K extends keyof RecipeFormValues>(name: K, value: RecipeFormValues[K]) => {
    // setFieldValue takes an updater union that a generic key can't narrow.
    form.setFieldValue(name, value as never);
    if (review.has(name as ReviewField)) {
      form.setFieldValue(
        "review",
        values.review.filter((field) => field !== name),
      );
    }
  };
  // Divine: the model estimates the macros from the ingredient lines. The
  // figures land in the fields flagged for a look, and nothing is saved until
  // the recipe is.
  const [divineMessage, setDivineMessage] = useState("");
  const divine = useMutation({
    mutationFn: estimateMacros,
    onSuccess: (macros) => {
      const text = (n: number | null) => (n === null ? "" : String(n));
      form.setFieldValue("macros", {
        calories: text(macros.calories),
        protein: text(macros.protein),
        carbs: text(macros.carbs),
        fat: text(macros.fat),
      });
      if (!form.state.values.review.includes("macros")) {
        form.setFieldValue("review", [...form.state.values.review, "macros"]);
      }
      setDivineMessage("");
    },
    onError: (error) =>
      setDivineMessage(
        error instanceof Error && "_tag" in error && error._tag === "Unavailable" && error.message
          ? error.message
          : copy.editor.divineFailed.text,
      ),
  });
  const divineMacros = () => {
    const { input } = toRecipeInput(values);
    const ingredients = input.ingredients
      .map((line) => (typeof line["original"] === "string" ? line["original"].trim() : ""))
      .filter((line) => line !== "");
    if (ingredients.length === 0) {
      setDivineMessage(copy.editor.divineNeedsIngredients.text);
      return;
    }
    const servings = input.servings;
    divine.mutate({
      title: input.title.trim() === "" ? null : input.title.trim(),
      servings:
        servings !== null &&
        Number.isInteger(servings) &&
        servings >= 1 &&
        servings <= RECIPE_LIMITS.servings
          ? servings
          : null,
      ingredients,
    });
  };

  const errorFor = (name: string) =>
    showAllErrors || submitted || touched.has(name) ? errors[name] : undefined;
  const listErrors = showAllErrors || submitted ? errors : {};
  const blur = (name: string) => () => setTouched((prev) => new Set(prev).add(name));

  const text = (
    name: Exclude<ReviewField, "tags" | "macros">,
    label: string,
    props: { mono?: boolean; inputMode?: "numeric" | "url"; multiline?: boolean } = {},
  ) => {
    const common = {
      label,
      name,
      value: values[name],
      error: errorFor(name),
      onBlur: blur(name),
      hint: review.has(name) ? copy.editor.needsALook.text : undefined,
    };
    return props.multiline ? (
      <div {...stylex.props(review.has(name) && styles.flagged)}>
        <Textarea {...common} onChange={(e) => setField(name, e.target.value)} />
      </div>
    ) : (
      <div {...stylex.props(review.has(name) && styles.flagged)}>
        <Input
          {...common}
          xstyle={props.mono ? styles.mono : undefined}
          inputMode={props.inputMode}
          type={props.inputMode === "url" ? "url" : "text"}
          onChange={(e) => setField(name, e.target.value)}
        />
      </div>
    );
  };

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        void submit();
      }}
      noValidate
      {...stylex.props(styles.form)}
    >
      <PageHeader
        title={title}
        actions={
          <div {...stylex.props(styles.headActions)}>
            <Status status={status} />
            {actions({ submit: () => void submit(), submitting })}
          </div>
        }
      />
      {intro}
      {submitted && Object.keys(errors).length > 0 ? (
        <FormMessage tone="error">{copy.editor.fixErrors.text}</FormMessage>
      ) : null}

      <div {...stylex.props(styles.titleField, review.has("title") && styles.flagged)}>
        <Input
          label={copy.editor.title.text}
          name="title"
          value={values.title}
          error={errorFor("title")}
          hint={review.has("title") ? copy.editor.needsALook.text : undefined}
          onBlur={blur("title")}
          onChange={(e) => setField("title", e.target.value)}
          autoComplete="off"
          xstyle={styles.titleInput}
        />
      </div>
      <PhotoField
        photoKey={values.photoKey}
        title={values.title}
        onChange={(photoKey) => form.setFieldValue("photoKey", photoKey)}
      />
      {text("description", copy.editor.description.text, { multiline: true })}

      <div {...stylex.props(styles.facts)}>
        {text("servings", copy.editor.servings.text, { mono: true, inputMode: "numeric" })}
        {text("prepMinutes", copy.editor.prepMinutes.text, { mono: true, inputMode: "numeric" })}
        {text("cookMinutes", copy.editor.cookMinutes.text, { mono: true, inputMode: "numeric" })}
        {text("totalMinutes", copy.editor.totalMinutes.text, { mono: true, inputMode: "numeric" })}
      </div>

      <fieldset {...stylex.props(styles.macros, review.has("macros") && styles.flagged)}>
        <legend {...stylex.props(styles.macrosLegend)}>{copy.editor.macros.text}</legend>
        <div {...stylex.props(styles.macrosHead)}>
          <p {...stylex.props(styles.macrosHint)}>
            {review.has("macros") ? copy.editor.divined.text : copy.editor.macrosHint.text}
          </p>
          <Button
            variant="secondary"
            onClick={divineMacros}
            disabled={divine.isPending}
            aria-describedby="divine-status"
          >
            {divine.isPending ? copy.editor.divining.text : copy.editor.divineMacros.text}
          </Button>
        </div>
        <p id="divine-status" role="status" {...stylex.props(styles.macrosHint)}>
          {divineMessage}
        </p>
        <div {...stylex.props(styles.facts)}>
          {MACRO_KEYS.map((key) => (
            <Input
              key={key}
              label={copy.editor.macroFields[key].text}
              name={`macros.${key}`}
              value={values.macros[key]}
              error={errorFor(`macros.${key}`)}
              onBlur={blur(`macros.${key}`)}
              xstyle={styles.mono}
              inputMode={key === "calories" ? "numeric" : "decimal"}
              onChange={(e) => setField("macros", { ...values.macros, [key]: e.target.value })}
            />
          ))}
        </div>
      </fieldset>

      <TagInput
        tags={values.tags}
        onChange={(next) => setField("tags", next)}
        suggestions={(tags.data ?? []).map((tag) => tag.name)}
        error={errorFor("tags")}
        flagged={review.has("tags")}
      />
      {text("sourceUrl", copy.editor.sourceUrl.text, { inputMode: "url" })}

      <section aria-labelledby="ingredients-heading" {...stylex.props(styles.section)}>
        <h2 id="ingredients-heading" {...stylex.props(styles.sectionTitle)}>
          {copy.editor.ingredients.text}
        </h2>
        <p {...stylex.props(styles.hint)}>{copy.editor.ingredientsHint.text}</p>
        <IngredientRows
          rows={values.ingredients}
          onChange={(rows) => form.setFieldValue("ingredients", rows)}
          errors={listErrors}
        />
      </section>

      <section aria-labelledby="steps-heading" {...stylex.props(styles.section)}>
        <h2 id="steps-heading" {...stylex.props(styles.sectionTitle)}>
          {copy.editor.steps.text}
        </h2>
        <p {...stylex.props(styles.hint)}>{copy.editor.stepsHint.text}</p>
        <StepRows
          rows={values.steps}
          onChange={(rows) => form.setFieldValue("steps", rows)}
          errors={listErrors}
        />
      </section>

      {text("notes", copy.editor.notes.text, { multiline: true })}

      <Dialog
        open={blocker.status === "blocked"}
        onClose={() => blocker.reset?.()}
        title={copy.editor.leaveTitle.text}
      >
        <p {...stylex.props(styles.dialogBody)}>{copy.editor.leaveBody.text}</p>
        <div {...stylex.props(styles.headActions)}>
          <Button variant="secondary" data-autofocus onClick={() => blocker.reset?.()}>
            {copy.editor.stay.text}
          </Button>
          <Button variant="danger" onClick={() => blocker.proceed?.()}>
            {copy.editor.leave.text}
          </Button>
        </div>
      </Dialog>
    </form>
  );
}

/** "Simmering…" while a change waits or saves, "Set" once it has landed. */
export function Status({ status }: { status: SaveStatus }) {
  const label =
    status === "pending" || status === "saving"
      ? copy.recipes.saving.text
      : status === "saved"
        ? copy.recipes.saved.text
        : status === "kept"
          ? copy.editor.draftKept.text
          : status === "error"
            ? copy.editor.couldntSave.text
            : status === "invalid"
              ? copy.editor.fixErrors.text
              : "";
  const hot =
    status === "pending" || status === "saving" || status === "error" || status === "invalid";
  return (
    <span role="status" {...stylex.props(styles.status)}>
      {label ? (
        <span aria-hidden="true" {...stylex.props(styles.dot, hot && styles.dotHot)} />
      ) : null}
      {label}
    </span>
  );
}

const styles = stylex.create({
  form: { display: "flex", flexDirection: "column", gap: 20, maxWidth: 820 },
  headActions: { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 12 },
  titleField: { borderRadius: 12 },
  titleInput: { fontSize: 22, fontWeight: 700, letterSpacing: "-0.015em" },
  facts: {
    display: "grid",
    gridTemplateColumns: {
      default: "repeat(4, minmax(0, 1fr))",
      "@media (max-width: 640px)": "repeat(2, minmax(0, 1fr))",
    },
    gap: 12,
  },
  mono: { fontFamily: fonts.mono },
  macros: {
    display: "flex",
    flexDirection: "column",
    gap: 8,
    margin: 0,
    padding: 0,
    borderWidth: 0,
    minWidth: 0,
  },
  macrosLegend: {
    padding: 0,
    marginBottom: 4,
    fontFamily: fonts.mono,
    fontSize: 10.5,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  macrosHint: { margin: 0, fontSize: 13, color: colors.subtext },
  macrosHead: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
  },
  // Import fields to confirm get the Tips color around them.
  flagged: {
    padding: 8,
    borderRadius: 12,
    backgroundColor: `color-mix(in srgb, ${colors.tips} 10%, transparent)`,
    outline: `1px solid color-mix(in srgb, ${colors.tips} 45%, transparent)`,
  },
  section: { display: "flex", flexDirection: "column", gap: 8 },
  sectionTitle: {
    margin: 0,
    fontSize: type.sectionSize,
    fontWeight: type.sectionWeight,
  },
  hint: { margin: 0, fontSize: 13, color: colors.subtext, maxWidth: "62ch" },
  status: {
    display: "inline-flex",
    alignItems: "center",
    gap: 6,
    minHeight: 20,
    fontFamily: fonts.mono,
    fontSize: 12,
    color: colors.subtext,
  },
  dot: { width: 7, height: 7, borderRadius: "50%", backgroundColor: colors.fresh },
  // Peach is the unsaved dot in the brand book.
  dotHot: { backgroundColor: colors.heat },
  dialogBody: { margin: 0, color: colors.subtext },
});
