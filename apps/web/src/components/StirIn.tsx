import * as stylex from "@stylexjs/stylex";
import {
  addDays,
  copy,
  formatTimer,
  MEAL_SLOTS,
  PLAN_LIMITS,
  type MealSlot,
  type PlanEntryInput,
  type PlanRecipe,
  recipeMinutes,
  toPlanRecipe,
} from "@cauldron/shared";
import { useDebouncedValue } from "@tanstack/react-pacer";
import { useInfiniteQuery } from "@tanstack/react-query";
import { type FormEvent, useEffect, useState } from "react";
import { dayLabel } from "../lib/dates";
import { savedWeekStartDay } from "../lib/plan";
import { libraryQuery, localToday } from "../lib/recipes";
import { usePlanWrites } from "../lib/use-plan";
import { colors, fonts } from "../styles/tokens.stylex";
import { Button, Dialog, Input, Select, useToast } from "./ui";
import { control, focusRing } from "./ui/controls";

// Stirring into the week, two ways: from an empty meal (pick a recipe or write
// a meal), and from a recipe page (pick the day and meal).

/** Searches the recipe box. Shared by the meal picker and the week's recipe panel. */
export function useRecipeSearch(text: string) {
  const [q] = useDebouncedValue(text.trim(), { wait: 150 });
  const results = useInfiniteQuery({
    ...libraryQuery({ q, tag: undefined, sort: q === "" ? "lastCooked" : "recent" }),
    placeholderData: (previous) => previous,
  });
  return {
    recipes: results.data?.pages.flatMap((page) => page.items).slice(0, 30) ?? [],
    loading: results.isPending,
  };
}

/** Pick what goes into one day's meal: a recipe from the box, or a line of text. */
export function PickMealDialog({
  target,
  onClose,
  onPick,
}: {
  target: { date: string; slot: MealSlot } | null;
  onClose: () => void;
  onPick: (choice: { recipe: PlanRecipe } | { title: string }) => void;
}) {
  const [text, setText] = useState("");
  const [meal, setMeal] = useState("");
  const { recipes, loading } = useRecipeSearch(text);
  useEffect(() => {
    if (target === null) {
      setText("");
      setMeal("");
    }
  }, [target]);

  const write = (e: FormEvent) => {
    e.preventDefault();
    if (meal.trim() === "") return;
    onPick({ title: meal.trim() });
  };

  const title = target
    ? copy.week.stirInto(dayLabel(target.date, "long"), copy.week.slots[target.slot].text).text
    : copy.week.stirIn.text;

  return (
    <Dialog open={target !== null} onClose={onClose} title={title}>
      <input
        type="search"
        aria-label={copy.week.searchRecipes.text}
        placeholder={copy.week.searchRecipes.text}
        autoComplete="off"
        value={text}
        onChange={(e) => setText(e.target.value)}
        data-autofocus
        {...stylex.props(control.field)}
      />
      <ul {...stylex.props(styles.results)}>
        {recipes.map((recipe) => {
          const minutes = recipeMinutes(recipe);
          return (
            <li key={recipe.id}>
              <button
                type="button"
                onClick={() => onPick({ recipe: toPlanRecipe(recipe) })}
                {...stylex.props(styles.result, focusRing.ring)}
              >
                <span {...stylex.props(styles.resultTitle)}>{recipe.title}</span>
                {minutes ? (
                  <span {...stylex.props(styles.detail)}>{formatTimer(minutes * 60)}</span>
                ) : null}
              </button>
            </li>
          );
        })}
        {!loading && recipes.length === 0 ? (
          <li {...stylex.props(styles.none)}>{copy.week.noMatches.text}</li>
        ) : null}
      </ul>
      <form onSubmit={write} {...stylex.props(styles.write)}>
        <div {...stylex.props(styles.grow)}>
          <Input
            label={copy.week.orWrite.text}
            placeholder={copy.week.writePlaceholder.text}
            maxLength={PLAN_LIMITS.title}
            value={meal}
            onChange={(e) => setMeal(e.target.value)}
          />
        </div>
        <Button type="submit" variant="secondary" disabled={meal.trim() === ""}>
          {copy.week.add.text}
        </Button>
      </form>
    </Dialog>
  );
}

/** From a recipe page: choose a day in the next two weeks and a meal. */
export function StirRecipeDialog({
  recipe,
  open,
  onClose,
}: {
  recipe: Parameters<typeof toPlanRecipe>[0];
  open: boolean;
  onClose: () => void;
}) {
  const toast = useToast();
  const writes = usePlanWrites(savedWeekStartDay());
  const [today, setToday] = useState(localToday);
  const [date, setDate] = useState(today);
  const [slot, setSlot] = useState<MealSlot>("dinner");
  useEffect(() => {
    if (!open) return;
    const now = localToday();
    setToday(now);
    setDate(now);
  }, [open]);

  const days = Array.from({ length: 14 }, (_, i) => addDays(today, i));

  // Optimistic like every plan write: the dialog closes at once, and the
  // entry carries its own id so a retried add can't plan it twice.
  const submit = (e: FormEvent) => {
    e.preventDefault();
    onClose();
    const input: PlanEntryInput = { date, slot, recipeId: recipe.id };
    void writes.stir(input, toPlanRecipe(recipe)).then((landed) => {
      if (landed) toast(copy.week.stirred(dayLabel(date, "long")).text);
    });
  };

  return (
    <Dialog open={open} onClose={onClose} title={copy.week.stirIntoWeek.text}>
      <form onSubmit={submit} {...stylex.props(styles.form)}>
        <Select label={copy.week.day.text} value={date} onChange={(e) => setDate(e.target.value)}>
          {days.map((day) => (
            <option key={day} value={day}>
              {dayLabel(day, "long")}
              {day === today ? ` (${copy.week.today.text})` : ""}
            </option>
          ))}
        </Select>
        <Select
          label={copy.week.slot.text}
          value={slot}
          onChange={(e) => setSlot(e.target.value as MealSlot)}
        >
          {MEAL_SLOTS.map((s) => (
            <option key={s} value={s}>
              {copy.week.slots[s].text}
            </option>
          ))}
        </Select>
        <div {...stylex.props(styles.actions)}>
          <Button variant="secondary" onClick={onClose}>
            {copy.week.cancel.text}
          </Button>
          <Button type="submit">
            {copy.week.stirInto(dayLabel(date, "short"), copy.week.slots[slot].text).text}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

const styles = stylex.create({
  results: {
    listStyle: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
    gap: 2,
    maxHeight: "min(40vh, 320px)",
    overflowY: "auto",
  },
  result: {
    width: "100%",
    display: "flex",
    alignItems: "baseline",
    justifyContent: "space-between",
    gap: 12,
    minHeight: 40,
    paddingBlock: 8,
    paddingInline: 10,
    borderWidth: 0,
    borderRadius: 8,
    backgroundColor: {
      default: "transparent",
      ":hover": `color-mix(in srgb, ${colors.magic} 18%, transparent)`,
    },
    color: colors.ink,
    fontSize: 15,
    textAlign: "start",
    cursor: "pointer",
  },
  resultTitle: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" },
  detail: { flexShrink: 0, fontFamily: fonts.mono, fontSize: 12, color: colors.subtext },
  none: { paddingBlock: 8, paddingInline: 10, fontSize: 14, color: colors.subtext },
  write: { display: "flex", alignItems: "flex-end", gap: 8 },
  grow: { flexGrow: 1, minWidth: 0 },
  form: { display: "flex", flexDirection: "column", gap: 14 },
  actions: { display: "flex", justifyContent: "flex-end", flexWrap: "wrap", gap: 8 },
});
