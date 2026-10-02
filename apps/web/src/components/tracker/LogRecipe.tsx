import * as stylex from "@stylexjs/stylex";
import {
  addDays,
  copy,
  type DiaryEntryInput,
  entryTotals,
  formatTimer,
  hasGaps,
  type Macros,
  MEAL_SLOTS,
  type MealSlot,
  type RecipeId,
  recipeMinutes,
  type RecipeSummary,
  TRACKER_LIMITS,
} from "@cauldron/shared";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useState } from "react";
import { messageOr } from "../../lib/api-failure";
import { dayLabel } from "../../lib/dates";
import { useDiaryWrites } from "../../lib/diary-writes";
import { estimateMacros, localToday, recipeQuery } from "../../lib/recipes";
import { colors, fonts } from "../../styles/tokens.stylex";
import { useRecipeSearch } from "../StirIn";
import { Button, Dialog, FormMessage, Input, Select } from "../ui";
import { control, focusRing } from "../ui/controls";

// Log a recipe (#115): pick one of your recipes, set the servings (fractions
// are fine), choose the meal, log it. The recipe's per-serving numbers are
// copied onto the entry. A recipe missing numbers can have them divined from
// its ingredients first, or be logged with the gap showing.

/** What logging needs from a recipe; a summary or a full recipe will do. */
export interface LoggableRecipe {
  readonly id: RecipeId;
  readonly title: string;
  readonly macros: Macros;
}

const SERVING_STEP = 0.25;
const QUICK_SERVINGS = [0.5, 1, 1.5, 2] as const;

/** The meal the hour suggests, for logging from outside the diary. */
export const slotForNow = (hour = new Date().getHours()): MealSlot =>
  hour < 11 ? "breakfast" : hour < 15 ? "lunch" : hour < 21 ? "dinner" : "snack";

const whole = (n: number) => Math.round(n).toLocaleString();

/** Search the recipe box, then log the one picked. Lives in the diary's add sheet. */
export function RecipePicker({
  date,
  slot,
  onLog,
}: {
  date: string;
  slot: MealSlot;
  onLog: (inputs: ReadonlyArray<DiaryEntryInput>) => void;
}) {
  const [text, setText] = useState("");
  const [picked, setPicked] = useState<RecipeSummary | null>(null);
  const { recipes, loading } = useRecipeSearch(text);

  if (picked) {
    return (
      <RecipeLogForm
        recipe={picked}
        date={date}
        slot={slot}
        onLog={onLog}
        onBack={() => setPicked(null)}
      />
    );
  }
  return (
    <div {...stylex.props(styles.form)}>
      <input
        type="search"
        aria-label={copy.tracker.logRecipe.search.text}
        placeholder={copy.tracker.logRecipe.search.text}
        autoComplete="off"
        value={text}
        onChange={(e) => setText(e.target.value)}
        {...stylex.props(control.field)}
      />
      <ul {...stylex.props(styles.results)}>
        {recipes.slice(0, 8).map((recipe) => {
          const minutes = recipeMinutes(recipe);
          const kcal = recipe.macros.calories;
          return (
            <li key={recipe.id}>
              <button
                type="button"
                onClick={() => setPicked(recipe)}
                {...stylex.props(styles.result, focusRing.ring)}
              >
                <span {...stylex.props(styles.resultTitle)}>{recipe.title}</span>
                <span {...stylex.props(styles.detail)}>
                  {kcal === null
                    ? copy.tracker.logRecipe.noNumbers.text
                    : `${whole(kcal)} ${copy.tracker.macros.calories.text} ${copy.tracker.logRecipe.aServing.text}`}
                  {minutes ? ` · ${formatTimer(minutes * 60)}` : ""}
                </span>
              </button>
            </li>
          );
        })}
        {!loading && recipes.length === 0 ? (
          <li {...stylex.props(styles.none)}>{copy.week.noMatches.text}</li>
        ) : null}
      </ul>
    </div>
  );
}

/** Servings, meal (and day, outside the diary) for one recipe, then log it. */
export function RecipeLogForm({
  recipe,
  date: initialDate,
  slot: initialSlot,
  chooseDay = false,
  onLog,
  onBack,
}: {
  recipe: LoggableRecipe;
  date: string;
  slot: MealSlot;
  /** Show a day picker: when logging from a recipe page or cook mode. */
  chooseDay?: boolean;
  onLog: (inputs: ReadonlyArray<DiaryEntryInput>) => void;
  onBack?: () => void;
}) {
  const queryClient = useQueryClient();
  const [servings, setServings] = useState("1");
  const [slot, setSlot] = useState<MealSlot>(initialSlot);
  const [date, setDate] = useState(initialDate);
  const [macros, setMacros] = useState<Macros>(recipe.macros);
  const [divined, setDivined] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const n = Number(servings);
  const servingsOk =
    servings.trim() !== "" && Number.isFinite(n) && n > 0 && n <= TRACKER_LIMITS.servings;
  const totals = entryTotals({ macros, servings: servingsOk ? n : 0 });
  const gaps = hasGaps({ macros });

  const divine = useMutation({
    mutationFn: async () => {
      const full = await queryClient.fetchQuery(recipeQuery(recipe.id));
      const ingredients = full.ingredients
        .map((line) => line.original.trim())
        .filter((line) => line !== "");
      if (ingredients.length === 0) throw new Error("no ingredients");
      return estimateMacros({ title: full.title, servings: full.servings, ingredients });
    },
    onMutate: () => setError(null),
    onSuccess: (estimate) => {
      // Keep what the recipe knows; fill only the gaps.
      setMacros({
        calories: recipe.macros.calories ?? estimate.calories,
        protein: recipe.macros.protein ?? estimate.protein,
        carbs: recipe.macros.carbs ?? estimate.carbs,
        fat: recipe.macros.fat ?? estimate.fat,
      });
      setDivined(true);
    },
    onError: (e) =>
      setError(
        e instanceof Error && e.message === "no ingredients"
          ? copy.editor.divineNeedsIngredients.text
          : messageOr(e, copy.editor.divineFailed.text),
      ),
  });

  const nudge = (by: number) =>
    setServings(String(+Math.max(SERVING_STEP, (servingsOk ? n : 1) + by).toFixed(2)));

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (!servingsOk) {
      return setError(copy.validation.numberBetween(0, TRACKER_LIMITS.servings).text);
    }
    onLog([
      {
        date,
        slot,
        name: recipe.title,
        servings: n,
        source: "recipe",
        recipeId: recipe.id,
        // Copied now, so later edits to the recipe leave this day alone.
        macros,
      },
    ]);
  };

  const today = localToday();
  const days = Array.from({ length: 8 }, (_, i) => addDays(today, -i));

  return (
    <form onSubmit={submit} noValidate {...stylex.props(styles.form)}>
      <div {...stylex.props(styles.recipeHead)}>
        <span {...stylex.props(styles.recipeTitle)}>{recipe.title}</span>
        {onBack ? (
          <Button variant="ghost" onClick={onBack}>
            {copy.tracker.logRecipe.change.text}
          </Button>
        ) : null}
      </div>

      <div {...stylex.props(styles.servingsRow)}>
        <Button
          variant="secondary"
          aria-label={copy.tracker.entry.fewer.text}
          onClick={() => nudge(-SERVING_STEP)}
        >
          −
        </Button>
        <Input
          label={copy.tracker.entry.servings.text}
          inputMode="decimal"
          value={servings}
          onChange={(e) => setServings(e.target.value)}
          xstyle={styles.servings}
        />
        <Button
          variant="secondary"
          aria-label={copy.tracker.entry.more.text}
          onClick={() => nudge(SERVING_STEP)}
        >
          +
        </Button>
      </div>
      <div
        role="group"
        aria-label={copy.tracker.entry.servings.text}
        {...stylex.props(styles.chips)}
      >
        {QUICK_SERVINGS.map((q) => (
          <button
            key={q}
            type="button"
            aria-pressed={servingsOk && n === q}
            onClick={() => setServings(String(q))}
            {...stylex.props(styles.chip, servingsOk && n === q && styles.chipOn, focusRing.ring)}
          >
            {q === 0.5 ? "½" : q === 1.5 ? "1½" : q}
          </button>
        ))}
      </div>

      <p {...stylex.props(styles.total)}>
        {copy.tracker.entry.total.text}{" "}
        <span {...stylex.props(styles.mono)}>
          {whole(totals.calories)} {copy.tracker.macros.calories.text} · {whole(totals.protein)}
          {copy.tracker.macros.grams.text} {copy.tracker.macros.protein.text} ·{" "}
          {whole(totals.carbs)}
          {copy.tracker.macros.grams.text} {copy.tracker.macros.carbs.text} · {whole(totals.fat)}
          {copy.tracker.macros.grams.text} {copy.tracker.macros.fat.text}
        </span>
        {divined ? (
          <span {...stylex.props(styles.tag)}> {copy.tracker.diary.estimate.text}</span>
        ) : null}
      </p>

      {gaps ? (
        <div {...stylex.props(styles.gap)}>
          <p {...stylex.props(styles.gapText)}>{copy.tracker.logRecipe.gaps.text}</p>
          <Button variant="secondary" onClick={() => divine.mutate()} disabled={divine.isPending}>
            {divine.isPending ? copy.editor.divining.text : copy.editor.divineMacros.text}
          </Button>
        </div>
      ) : null}

      <div {...stylex.props(styles.row)}>
        <Select
          label={copy.tracker.entry.meal.text}
          value={slot}
          onChange={(e) => setSlot(e.target.value as MealSlot)}
        >
          {MEAL_SLOTS.map((s) => (
            <option key={s} value={s}>
              {copy.week.slots[s].text}
            </option>
          ))}
        </Select>
        {chooseDay ? (
          <Select
            label={copy.tracker.entry.day.text}
            value={date}
            onChange={(e) => setDate(e.target.value)}
          >
            {days.map((d) => (
              <option key={d} value={d}>
                {d === today ? copy.tracker.diary.today.text : dayLabel(d, "short")}
              </option>
            ))}
          </Select>
        ) : null}
      </div>
      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      <div {...stylex.props(styles.actions)}>
        <Button type="submit">{copy.tracker.entry.log.text}</Button>
      </div>
    </form>
  );
}

/** "Log it" from a recipe page or the end of cook mode: today, the meal the hour suggests. */
export function LogRecipeDialog({
  recipe,
  open,
  onClose,
  onLogged,
}: {
  recipe: LoggableRecipe;
  open: boolean;
  onClose: () => void;
  onLogged?: () => void;
}) {
  const writes = useDiaryWrites();
  return (
    <Dialog open={open} onClose={onClose} title={copy.tracker.logRecipe.title.text}>
      {open ? (
        <RecipeLogForm
          recipe={recipe}
          date={localToday()}
          slot={slotForNow()}
          chooseDay
          onLog={(inputs) => {
            onClose();
            void writes.add(inputs).then((ok) => ok && onLogged?.());
          }}
        />
      ) : null}
    </Dialog>
  );
}

const styles = stylex.create({
  form: { display: "flex", flexDirection: "column", gap: 12 },
  results: {
    listStyle: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
    maxHeight: 280,
    overflowY: "auto",
  },
  result: {
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-start",
    gap: 2,
    width: "100%",
    paddingBlock: 8,
    paddingInline: 10,
    borderRadius: 8,
    borderWidth: 0,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
    textAlign: "start",
    cursor: "pointer",
    fontFamily: fonts.ui,
  },
  resultTitle: { fontSize: 15, fontWeight: 500 },
  detail: { fontFamily: fonts.mono, fontSize: 12, color: colors.subtext },
  none: { paddingBlock: 8, paddingInline: 10, fontSize: 14, color: colors.subtext },
  recipeHead: { display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 },
  recipeTitle: { fontSize: 16, fontWeight: 600 },
  servingsRow: { display: "flex", alignItems: "flex-end", gap: 8 },
  servings: { fontFamily: fonts.mono, textAlign: "center", fontVariantNumeric: "tabular-nums" },
  chips: { display: "flex", gap: 6 },
  chip: {
    minWidth: 44,
    paddingBlock: 6,
    paddingInline: 10,
    borderRadius: 999,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface1,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
    fontFamily: fonts.mono,
    fontSize: 13,
    cursor: "pointer",
  },
  chipOn: { borderColor: colors.magic, backgroundColor: colors.surface0 },
  total: { margin: 0, fontSize: 13, color: colors.subtext },
  mono: { fontFamily: fonts.mono, color: colors.ink, fontVariantNumeric: "tabular-nums" },
  tag: {
    fontFamily: fonts.mono,
    fontSize: 10.5,
    letterSpacing: "0.04em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  gap: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
    padding: 10,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "dashed",
    borderColor: colors.tips,
  },
  gapText: { margin: 0, fontSize: 13, color: colors.ink },
  row: {
    display: "grid",
    gridTemplateColumns: { default: "1fr 1fr", "@media (max-width: 480px)": "1fr" },
    gap: 10,
  },
  actions: { display: "flex", justifyContent: "flex-end", gap: 8 },
});
