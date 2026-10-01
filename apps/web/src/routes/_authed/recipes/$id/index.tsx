import * as stylex from "@stylexjs/stylex";
import {
  copy,
  displayMeasure,
  formatQuantity,
  formatTimer,
  type Ingredient,
  photoUrl,
  type Recipe,
  type Tag,
  type UnitSystemChoice,
} from "@cauldron/shared";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import {
  Button,
  ButtonLink,
  Dialog,
  EmptyState,
  PageHeader,
  Skeleton,
  useToast,
} from "../../../../components/ui";
import { StirRecipeDialog } from "../../../../components/StirIn";
import { focusRing } from "../../../../components/ui/controls";
import {
  banishRecipe,
  duplicateRecipe,
  localToday,
  markCooked,
  recipeQuery,
  restoreRecipe,
  settleRecipe,
} from "../../../../lib/recipes";
import { colors, fonts, quantity, type } from "../../../../styles/tokens.stylex";

export const Route = createFileRoute("/_authed/recipes/$id/")({ component: RecipePage });

const isNotFound = (error: unknown) =>
  typeof error === "object" && error !== null && "_tag" in error && error._tag === "NotFound";

function RecipePage() {
  const { id } = Route.useParams();
  const recipe = useQuery(recipeQuery(id));
  if (recipe.isPending) {
    return (
      <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.loading)}>
        <Skeleton height={40} width="60%" />
        <Skeleton width="40%" />
        <Skeleton height={200} />
      </div>
    );
  }
  if (recipe.isError) {
    return (
      <EmptyState
        message={
          isNotFound(recipe.error) ? copy.recipeView.notFound.text : copy.errors.internal.text
        }
        actions={
          <ButtonLink to="/recipes" variant="secondary">
            {copy.recipeView.backToRecipes.text}
          </ButtonLink>
        }
      />
    );
  }
  return <RecipeView key={id} recipe={recipe.data} />;
}

// ---------------------------------------------------------------------------
// Scaling: by servings when the recipe has them, otherwise by a multiplier.

const MULTIPLIERS = [0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 8];
const UNIT_KEY = "cauldron:units";

const factorLabel = (factor: number) => formatQuantity({ min: factor, max: null }, null);

/** The unit choice is a per-viewer preference, remembered in this browser. */
function useUnitChoice() {
  const [units, setUnits] = useState<UnitSystemChoice>("asWritten");
  useEffect(() => {
    try {
      const saved = window.localStorage.getItem(UNIT_KEY);
      if (saved === "metric" || saved === "us" || saved === "asWritten") setUnits(saved);
    } catch {
      // Storage is optional.
    }
  }, []);
  const choose = (next: UnitSystemChoice) => {
    setUnits(next);
    try {
      window.localStorage.setItem(UNIT_KEY, next);
    } catch {
      // Storage is optional.
    }
  };
  return [units, choose] as const;
}

const minutes = (value: number) => formatTimer(value * 60);

const dateLabel = (day: string) =>
  new Date(`${day}T12:00:00`).toLocaleDateString(undefined, { month: "short", day: "numeric" });

const hostOf = (url: string) => {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
};

function RecipeView({ recipe }: { recipe: Recipe }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const toast = useToast();
  const [servings, setServings] = useState(recipe.servings);
  const [multiplier, setMultiplier] = useState(1);
  const [units, setUnits] = useUnitChoice();
  const [checked, setChecked] = useState<ReadonlySet<number>>(new Set());
  const [confirmingBanish, setConfirmingBanish] = useState(false);
  const [stirring, setStirring] = useState(false);
  const [busy, setBusy] = useState(false);

  const factor =
    recipe.servings !== null && servings !== null ? servings / recipe.servings : multiplier;
  const total =
    recipe.totalMinutes ??
    (recipe.prepMinutes !== null || recipe.cookMinutes !== null
      ? (recipe.prepMinutes ?? 0) + (recipe.cookMinutes ?? 0)
      : null);

  const step = (direction: 1 | -1) => {
    if (servings !== null) {
      return setServings((n) => Math.min(1000, Math.max(1, (n ?? 1) + direction)));
    }
    setMultiplier((m) => {
      const index = MULTIPLIERS.indexOf(m) + direction;
      return MULTIPLIERS[Math.min(MULTIPLIERS.length - 1, Math.max(0, index))]!;
    });
  };

  const toggle = (index: number) =>
    setChecked((prev) => {
      const next = new Set(prev);
      if (!next.delete(index)) next.add(index);
      return next;
    });

  const run = async (action: () => Promise<void>) => {
    setBusy(true);
    try {
      await action();
    } catch {
      toast(copy.errors.internal.text, "error");
    } finally {
      setBusy(false);
    }
  };

  const banish = () =>
    run(async () => {
      setConfirmingBanish(false);
      await banishRecipe(recipe.id);
      // A banished recipe reads as not found: drop it, and refresh lists and tags.
      queryClient.removeQueries({ queryKey: recipeQuery(recipe.id).queryKey });
      void queryClient.invalidateQueries({ queryKey: ["recipes"] });
      void queryClient.invalidateQueries({ queryKey: ["tags"] });
      await navigate({ to: "/recipes" });
      toast(copy.recipeView.banished(recipe.title).text, "info", {
        label: copy.recipeView.undo.text,
        onClick: () => {
          void restoreRecipe(recipe.id).then(
            (restored) => {
              settleRecipe(queryClient, restored);
              toast(copy.recipeView.restored.text);
            },
            () => toast(copy.errors.internal.text, "error"),
          );
        },
      });
    });

  const duplicate = () =>
    run(async () => {
      const copyOf = await duplicateRecipe(recipe.id);
      settleRecipe(queryClient, copyOf);
      await navigate({ to: "/recipes/$id/edit", params: { id: copyOf.id } });
      toast(copy.recipeView.duplicated.text);
    });

  const brewed = () =>
    run(async () => {
      settleRecipe(queryClient, await markCooked(recipe.id, localToday()));
      toast(copy.recipeView.brewedToday.text);
    });

  const lineCount = recipe.ingredients.length;
  const banishCopy = copy.recipes.banishConfirm(recipe.title);
  let section: string | null = null;

  return (
    <article {...stylex.props(styles.page)}>
      <PageHeader
        title={recipe.title}
        actions={
          <div data-print="hide" {...stylex.props(styles.actions)}>
            <ButtonLink to="/recipes/$id/edit" params={{ id: recipe.id }} variant="secondary">
              {copy.recipeView.edit.text}
            </ButtonLink>
            <Button variant="secondary" onClick={brewed} disabled={busy}>
              {copy.recipeView.markBrewed.text}
            </Button>
            <ButtonLink
              to="/brew/$id"
              params={{ id: recipe.id }}
              search={servings !== null ? { servings } : {}}
              variant="secondary"
            >
              {copy.recipes.startBrewing.text}
            </ButtonLink>
            <Button onClick={() => setStirring(true)}>{copy.week.stirIntoWeek.text}</Button>
          </div>
        }
      />

      {recipe.photoKey ? (
        <img
          src={photoUrl(recipe.photoKey, "full")}
          srcSet={`${photoUrl(recipe.photoKey, "card")} 800w, ${photoUrl(recipe.photoKey, "full")} 1920w`}
          sizes="(max-width: 767px) 100vw, 1040px"
          alt={copy.photos.alt(recipe.title).text}
          {...stylex.props(styles.hero)}
        />
      ) : null}

      {recipe.description ? (
        <p {...stylex.props(styles.description)}>{recipe.description}</p>
      ) : null}

      <div {...stylex.props(styles.facts)}>
        {total !== null ? <span {...stylex.props(styles.chip)}>{minutes(total)}</span> : null}
        {recipe.prepMinutes !== null ? (
          <span {...stylex.props(styles.chip)}>
            {minutes(recipe.prepMinutes)} {copy.recipeView.prep.text}
          </span>
        ) : null}
        {recipe.cookMinutes !== null ? (
          <span {...stylex.props(styles.chip)}>
            {minutes(recipe.cookMinutes)} {copy.recipeView.cook.text}
          </span>
        ) : null}
        <span
          role="group"
          aria-label={copy.recipeView.servingsFor.text}
          {...stylex.props(styles.stepper)}
        >
          <button
            type="button"
            aria-label={copy.recipeView.fewer.text}
            disabled={servings !== null ? servings <= 1 : multiplier <= MULTIPLIERS[0]!}
            onClick={() => step(-1)}
            data-print="hide"
            {...stylex.props(styles.stepButton, focusRing.ring)}
          >
            −
          </button>
          <output aria-live="polite" {...stylex.props(styles.stepValue)}>
            {servings !== null
              ? copy.recipeView.serves(servings).text
              : copy.recipeView.scale(factorLabel(multiplier)).text}
          </output>
          <button
            type="button"
            aria-label={copy.recipeView.more.text}
            disabled={
              servings !== null
                ? servings >= 1000
                : multiplier >= MULTIPLIERS[MULTIPLIERS.length - 1]!
            }
            onClick={() => step(1)}
            data-print="hide"
            {...stylex.props(styles.stepButton, focusRing.ring)}
          >
            +
          </button>
        </span>
        {recipe.tags.map((tag) => (
          <TagChip key={tag.id} tag={tag} />
        ))}
      </div>

      {recipe.sourceUrl || recipe.lastCookedOn ? (
        <p {...stylex.props(styles.meta)}>
          {recipe.sourceUrl ? (
            <a
              href={recipe.sourceUrl}
              target="_blank"
              rel="noopener noreferrer nofollow"
              {...stylex.props(styles.link, focusRing.ring)}
            >
              {copy.recipeView.from(hostOf(recipe.sourceUrl)).text}
            </a>
          ) : null}
          {recipe.sourceAuthor ? (
            <span> {copy.recipeView.by(recipe.sourceAuthor).text}</span>
          ) : null}
          {recipe.lastCookedOn ? (
            <span {...stylex.props(styles.mono)}>
              {copy.recipeView.lastCooked(dateLabel(recipe.lastCookedOn)).text}
            </span>
          ) : null}
        </p>
      ) : null}

      <div {...stylex.props(styles.columns)}>
        <section aria-labelledby="ingredients-title">
          <div {...stylex.props(styles.columnHead)}>
            <h2 id="ingredients-title" {...stylex.props(styles.label)}>
              {copy.recipeView.ingredients.text}
            </h2>
            {lineCount > 0 ? (
              <span {...stylex.props(styles.label)} data-print="hide">
                {copy.recipeView.checked(checked.size, lineCount).text}
              </span>
            ) : null}
          </div>
          <fieldset data-print="hide" {...stylex.props(styles.units)}>
            <legend {...stylex.props(styles.srOnly)}>{copy.recipeView.units.text}</legend>
            {(["asWritten", "metric", "us"] as const).map((choice) => (
              <label
                key={choice}
                {...stylex.props(styles.unitOption, units === choice && styles.unitOn)}
              >
                <input
                  type="radio"
                  name="units"
                  value={choice}
                  checked={units === choice}
                  onChange={() => setUnits(choice)}
                  {...stylex.props(styles.srOnly)}
                />
                {copy.recipeView[choice].text}
              </label>
            ))}
          </fieldset>
          <ul {...stylex.props(styles.ingredients)}>
            {recipe.ingredients.map((line, index) => {
              const heading =
                line.section !== section && line.section !== null ? line.section : null;
              section = line.section;
              return (
                <IngredientLine
                  key={index}
                  line={line}
                  heading={heading}
                  done={checked.has(index)}
                  onToggle={() => toggle(index)}
                  factor={factor}
                  units={units}
                />
              );
            })}
          </ul>
        </section>

        <section aria-labelledby="method-title" {...stylex.props(styles.method)}>
          <h2 id="method-title" {...stylex.props(styles.label)}>
            {copy.recipeView.method.text}
          </h2>
          {/* role keeps list semantics in Safari, where list-style: none drops them. */}
          <ol role="list" {...stylex.props(styles.steps)}>
            {recipe.steps.map((s, index) => (
              <li key={index} {...stylex.props(styles.step)}>
                <span aria-hidden="true" {...stylex.props(styles.stepNumber)}>
                  {index + 1}
                </span>
                <span>
                  {s.text}
                  {s.timerSeconds !== null ? (
                    <span {...stylex.props(styles.timer)}>⏲ {formatTimer(s.timerSeconds)}</span>
                  ) : null}
                </span>
              </li>
            ))}
          </ol>
          {recipe.notes ? (
            <aside {...stylex.props(styles.callout)}>
              <span aria-hidden="true" {...stylex.props(styles.star)}>
                ✦
              </span>
              <p {...stylex.props(styles.notes)}>{recipe.notes}</p>
            </aside>
          ) : null}
        </section>
      </div>

      <footer data-print="hide" {...stylex.props(styles.footer)}>
        <Button variant="ghost" onClick={() => window.print()}>
          {copy.recipeView.print.text}
        </Button>
        <Button variant="ghost" onClick={duplicate} disabled={busy}>
          {copy.recipeView.duplicate.text}
        </Button>
        <Button variant="danger" onClick={() => setConfirmingBanish(true)} disabled={busy}>
          {banishCopy.verb.text}
        </Button>
      </footer>

      <StirRecipeDialog recipe={recipe} open={stirring} onClose={() => setStirring(false)} />

      <Dialog
        open={confirmingBanish}
        onClose={() => setConfirmingBanish(false)}
        title={banishCopy.verb.text}
      >
        <p {...stylex.props(styles.dialogText)}>{banishCopy.confirm.text}</p>
        <div {...stylex.props(styles.actions)}>
          <Button variant="secondary" data-autofocus onClick={() => setConfirmingBanish(false)}>
            {copy.recipeView.cancel.text}
          </Button>
          <Button variant="danger" onClick={banish} disabled={busy}>
            {banishCopy.verb.text}
          </Button>
        </div>
      </Dialog>
    </article>
  );
}

function IngredientLine({
  line,
  heading,
  done,
  onToggle,
  factor,
  units,
}: {
  line: Ingredient;
  heading: string | null;
  done: boolean;
  onToggle: () => void;
  factor: number;
  units: UnitSystemChoice;
}) {
  const measure = line.quantity ? displayMeasure(line.quantity, line.unit, factor, units) : null;
  const rest = [line.item, line.note].filter(Boolean).join(", ");
  return (
    <>
      {heading ? <li {...stylex.props(styles.section)}>{heading}</li> : null}
      <li>
        <label {...stylex.props(styles.line, done && styles.lineDone)}>
          <input
            type="checkbox"
            checked={done}
            onChange={onToggle}
            {...stylex.props(styles.check)}
          />
          <span {...stylex.props(styles.amount)}>
            {measure ? (
              <>
                {measure.amount}
                {measure.unit ? (
                  <span {...stylex.props(quantity.unit)}> {measure.unit}</span>
                ) : null}
              </>
            ) : null}
          </span>
          <span {...stylex.props(done && styles.struck)}>
            {rest}
            {line.optional ? (
              <span {...stylex.props(styles.optional)}> ({copy.recipeView.optional.text})</span>
            ) : null}
          </span>
        </label>
      </li>
    </>
  );
}

function TagChip({ tag }: { tag: Tag }) {
  // Meal tags take the Tips color and diet tags the Fresh color, as washes
  // behind ink text so they keep contrast in Latte.
  return (
    <span
      {...stylex.props(
        styles.tag,
        tag.kind === "meal" && styles.tagMeal,
        tag.kind === "diet" && styles.tagDiet,
      )}
    >
      {tag.name}
    </span>
  );
}

const phone = "@media (max-width: 767px)";

const styles = stylex.create({
  loading: { display: "grid", gap: 12, maxWidth: 720 },
  page: { display: "flex", flexDirection: "column", gap: 16, maxWidth: 1040 },
  actions: { display: "flex", flexWrap: "wrap", gap: 8 },
  hero: {
    width: "100%",
    maxHeight: 420,
    aspectRatio: "16 / 9",
    objectFit: "cover",
    borderRadius: 14,
    backgroundColor: colors.mantle,
  },
  description: {
    margin: 0,
    maxWidth: "62ch",
    fontSize: type.bodySize,
    lineHeight: type.bodyLeading,
    color: colors.subtext,
  },
  facts: { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 8 },
  chip: {
    fontFamily: fonts.mono,
    fontSize: 12.5,
    paddingBlock: 3,
    paddingInline: 10,
    borderRadius: 999,
    backgroundColor: colors.surface0,
    color: colors.ink,
  },
  stepper: {
    display: "inline-flex",
    alignItems: "center",
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface1,
    borderRadius: 8,
    overflow: "hidden",
  },
  stepButton: {
    width: { default: 32, [phone]: 44 },
    height: { default: 30, [phone]: 44 },
    opacity: { default: 1, ":disabled": 0.4 },
    cursor: { default: "pointer", ":disabled": "default" },
    borderWidth: 0,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
    fontFamily: fonts.mono,
    fontSize: 16,
  },
  stepValue: {
    paddingInline: 8,
    fontFamily: fonts.mono,
    fontSize: 13,
    fontWeight: 600,
    color: colors.ink,
    fontVariantNumeric: "tabular-nums",
  },
  tag: {
    fontSize: 12.5,
    fontWeight: 500,
    paddingBlock: 3,
    paddingInline: 10,
    borderRadius: 999,
    backgroundColor: colors.surface0,
    color: colors.ink,
  },
  tagMeal: { backgroundColor: `color-mix(in srgb, ${colors.tips} 24%, transparent)` },
  tagDiet: { backgroundColor: `color-mix(in srgb, ${colors.fresh} 24%, transparent)` },
  meta: {
    margin: 0,
    display: "flex",
    flexWrap: "wrap",
    gap: 12,
    fontSize: 13.5,
    color: colors.subtext,
  },
  mono: { fontFamily: fonts.mono, fontSize: 12.5 },
  link: {
    color: colors.ink,
    borderRadius: 4,
    textDecorationLine: "underline",
    textDecorationColor: colors.magic,
    textUnderlineOffset: 3,
  },
  columns: {
    display: "grid",
    gridTemplateColumns: {
      default: "minmax(240px, 320px) minmax(0, 1fr)",
      [phone]: "minmax(0, 1fr)",
    },
    gap: { default: 40, [phone]: 28 },
    marginTop: 8,
  },
  columnHead: { display: "flex", justifyContent: "space-between", alignItems: "baseline" },
  label: {
    margin: 0,
    marginBottom: 10,
    fontFamily: fonts.mono,
    fontSize: 11,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.subtext,
  },
  units: {
    display: "inline-flex",
    margin: 0,
    marginBottom: 10,
    padding: 2,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    borderRadius: 8,
  },
  unitOption: {
    position: "relative",
    paddingBlock: { default: 3, [phone]: 8 },
    paddingInline: 10,
    borderRadius: 6,
    fontSize: 12.5,
    color: colors.subtext,
    cursor: "pointer",
    outline: { default: "none", ":has(:focus-visible)": `2px solid ${colors.magic}` },
  },
  unitOn: { backgroundColor: colors.surface0, color: colors.ink, fontWeight: 600 },
  ingredients: { listStyle: "none", margin: 0, padding: 0 },
  section: {
    paddingTop: 14,
    paddingBottom: 4,
    fontSize: 14,
    fontWeight: 650,
    color: colors.ink,
  },
  line: {
    display: "grid",
    gridTemplateColumns: "18px minmax(76px, max-content) minmax(0, 1fr)",
    alignItems: "baseline",
    gap: 10,
    paddingBlock: { default: 7, [phone]: 10 },
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: colors.surface0,
    fontSize: 15,
    cursor: "pointer",
  },
  lineDone: { color: colors.overlay1 },
  check: { margin: 0, width: 16, height: 16, accentColor: colors.magic, alignSelf: "center" },
  amount: {
    textAlign: "end",
    fontFamily: fonts.mono,
    fontSize: 13.5,
    fontWeight: 500,
    fontVariantNumeric: "tabular-nums",
  },
  struck: { textDecorationLine: "line-through", textDecorationColor: colors.overlay0 },
  optional: { color: colors.subtext },
  method: { display: "flex", flexDirection: "column", gap: 0 },
  steps: { listStyle: "none", margin: 0, padding: 0, display: "grid", gap: 18 },
  step: {
    display: "grid",
    gridTemplateColumns: "26px minmax(0, 1fr)",
    gap: 12,
    fontSize: { default: 15, [phone]: 17 },
    lineHeight: type.bodyLeading,
  },
  stepNumber: {
    display: "grid",
    placeItems: "center",
    width: 26,
    height: 26,
    borderRadius: "50%",
    fontFamily: fonts.mono,
    fontSize: 12,
    fontWeight: 600,
    backgroundColor: `color-mix(in srgb, ${colors.magic} 18%, transparent)`,
    color: colors.ink,
  },
  timer: {
    display: "inline-flex",
    alignItems: "center",
    gap: 5,
    marginInlineStart: 6,
    paddingBlock: 1,
    paddingInline: 8,
    borderRadius: 999,
    fontFamily: fonts.mono,
    fontSize: 12,
    fontWeight: 500,
    whiteSpace: "nowrap",
    color: colors.ink,
    backgroundColor: `color-mix(in srgb, ${colors.heat} 18%, transparent)`,
  },
  callout: {
    display: "flex",
    gap: 12,
    marginTop: 20,
    paddingBlock: 11,
    paddingInline: 14,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: `color-mix(in srgb, ${colors.tips} 30%, transparent)`,
    backgroundColor: `color-mix(in srgb, ${colors.tips} 12%, ${colors.base})`,
    fontSize: 14,
  },
  star: { color: colors.tips },
  notes: { margin: 0, whiteSpace: "pre-wrap" },
  footer: {
    display: "flex",
    flexWrap: "wrap",
    gap: 8,
    marginTop: 24,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopStyle: "solid",
    borderTopColor: colors.surface0,
  },
  dialogText: { margin: 0, color: colors.subtext },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
});
