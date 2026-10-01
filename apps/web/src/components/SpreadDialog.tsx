import * as stylex from "@stylexjs/stylex";
import {
  copy,
  MEAL_SLOTS,
  type MealSlot,
  oneADay,
  PLAN_LIMITS,
  type PlanEntryInput,
  type RecipeId,
} from "@cauldron/shared";
import { type FormEvent, useEffect, useState } from "react";
import { dayLabel } from "../lib/dates";
import type { StirRecipe } from "../lib/use-plan";
import { colors, fonts } from "../styles/tokens.stylex";
import { Button, Dialog, Select } from "./ui";
import { focusRing } from "./ui/controls";

// Stirring a recipe into the week: pick the days its servings feed. A batch of
// five might be dinner tonight and lunch for the next four days. Each picked
// day is its own entry with its own servings, added together or not at all.

export interface Spreading {
  readonly date: string;
  readonly slot: MealSlot;
  readonly recipe: StirRecipe;
  /** Where in the first day's slot, when it was dropped on another meal. */
  readonly position?: number;
}

export function SpreadDialog({
  spreading,
  days,
  today,
  onClose,
  onStir,
}: {
  spreading: Spreading | null;
  /** The week being planned. */
  days: ReadonlyArray<string>;
  today: string;
  onClose: () => void;
  onStir: (inputs: ReadonlyArray<PlanEntryInput>, recipe: StirRecipe) => void;
}) {
  const [slot, setSlot] = useState<MealSlot>("dinner");
  const [plan, setPlan] = useState<ReadonlyMap<string, number>>(new Map());
  useEffect(() => {
    if (!spreading) return;
    setSlot(spreading.slot);
    setPlan(new Map([[spreading.date, 1]]));
  }, [spreading]);

  const recipeServings = spreading?.recipe.servings ?? null;
  const planned = [...plan.values()].reduce((a, b) => a + b, 0);
  const picked = days.filter((day) => plan.has(day));

  const toggle = (day: string) =>
    setPlan((current) => {
      const next = new Map(current);
      if (next.has(day)) next.delete(day);
      else next.set(day, 1);
      return next;
    });

  const step = (day: string, by: -1 | 1) =>
    setPlan((current) => {
      const n = (current.get(day) ?? 0) + by;
      const next = new Map(current);
      if (n <= 0) next.delete(day);
      else next.set(day, Math.min(n, PLAN_LIMITS.servings));
      return next;
    });

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (!spreading || picked.length === 0) return;
    onStir(
      picked.map((date) => ({
        date,
        slot,
        recipeId: spreading.recipe.id as RecipeId,
        servings: plan.get(date)!,
        ...(date === spreading.date && slot === spreading.slot && spreading.position !== undefined
          ? { position: spreading.position }
          : {}),
      })),
      spreading.recipe,
    );
  };

  return (
    <Dialog open={spreading !== null} onClose={onClose} title={spreading?.recipe.title ?? ""}>
      {spreading ? (
        <form onSubmit={submit} {...stylex.props(styles.form)}>
          <p {...stylex.props(styles.hint)}>{copy.week.spread.hint.text}</p>
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

          <fieldset {...stylex.props(styles.days)}>
            <legend {...stylex.props(styles.legend)}>{copy.week.spread.days.text}</legend>
            <div {...stylex.props(styles.quick)}>
              <Button
                variant="secondary"
                onClick={() => setPlan(oneADay(days, spreading.date, recipeServings))}
              >
                {copy.week.spread.oneADay.text}
              </Button>
              <Button
                variant="ghost"
                onClick={() =>
                  setPlan(new Map([[spreading.date, Math.max(1, recipeServings ?? 1)]]))
                }
              >
                {copy.week.spread.allOn(dayLabel(spreading.date, "short")).text}
              </Button>
            </div>
            <ul {...stylex.props(styles.list)}>
              {days.map((day) => {
                const n = plan.get(day);
                const on = n !== undefined;
                const label = dayLabel(day, "long");
                return (
                  <li
                    key={day}
                    {...stylex.props(styles.row, on && styles.rowOn, day < today && styles.past)}
                  >
                    <button
                      type="button"
                      aria-pressed={on}
                      onClick={() => toggle(day)}
                      {...stylex.props(styles.day, focusRing.ring)}
                    >
                      <span
                        aria-hidden="true"
                        {...stylex.props(styles.check, on && styles.checkOn)}
                      >
                        {on ? "✓" : ""}
                      </span>
                      <span {...stylex.props(day === today && styles.today)}>{label}</span>
                    </button>
                    {on ? (
                      <span role="group" aria-label={label} {...stylex.props(styles.stepper)}>
                        <button
                          type="button"
                          aria-label={copy.week.spread.fewer(label).text}
                          onClick={() => step(day, -1)}
                          {...stylex.props(styles.stepButton, focusRing.ring)}
                        >
                          −
                        </button>
                        <output aria-live="polite" {...stylex.props(styles.stepValue)}>
                          {copy.week.spread.servingsOn(n).text}
                        </output>
                        <button
                          type="button"
                          aria-label={copy.week.spread.more(label).text}
                          disabled={n >= PLAN_LIMITS.servings}
                          onClick={() => step(day, 1)}
                          {...stylex.props(styles.stepButton, focusRing.ring)}
                        >
                          +
                        </button>
                      </span>
                    ) : null}
                  </li>
                );
              })}
            </ul>
          </fieldset>

          <p
            aria-live="polite"
            {...stylex.props(
              styles.count,
              recipeServings !== null && planned > recipeServings && styles.over,
            )}
          >
            {picked.length === 0
              ? copy.week.spread.pickADay.text
              : copy.week.spread.planned(planned, recipeServings).text}
          </p>

          <div {...stylex.props(styles.actions)}>
            <Button variant="secondary" onClick={onClose}>
              {copy.week.cancel.text}
            </Button>
            <Button type="submit" disabled={picked.length === 0}>
              {copy.week.spread.stir(picked.length).text}
            </Button>
          </div>
        </form>
      ) : null}
    </Dialog>
  );
}

const styles = stylex.create({
  form: { display: "flex", flexDirection: "column", gap: 14 },
  hint: { margin: 0, fontSize: 14, color: colors.subtext },
  days: {
    display: "flex",
    flexDirection: "column",
    gap: 8,
    margin: 0,
    padding: 0,
    borderWidth: 0,
    minWidth: 0,
  },
  legend: {
    padding: 0,
    marginBottom: 6,
    fontFamily: fonts.mono,
    fontSize: 10.5,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  quick: { display: "flex", flexWrap: "wrap", gap: 8 },
  list: {
    listStyle: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
    gap: 4,
  },
  row: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
    minHeight: 44,
    paddingInlineEnd: 6,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
  },
  rowOn: {
    borderColor: colors.magic,
    backgroundColor: `color-mix(in srgb, ${colors.magic} 10%, transparent)`,
  },
  past: { opacity: 0.7 },
  day: {
    display: "flex",
    alignItems: "center",
    gap: 10,
    flexGrow: 1,
    minHeight: 42,
    paddingInline: 10,
    borderWidth: 0,
    borderRadius: 10,
    backgroundColor: "transparent",
    color: colors.ink,
    fontFamily: fonts.ui,
    fontSize: 14.5,
    textAlign: "start",
    cursor: "pointer",
  },
  check: {
    display: "grid",
    placeItems: "center",
    flexShrink: 0,
    width: 18,
    height: 18,
    borderRadius: 5,
    borderWidth: 1.5,
    borderStyle: "solid",
    borderColor: colors.overlay0,
    color: colors.base,
    fontSize: 12,
    fontWeight: 700,
  },
  checkOn: { backgroundColor: colors.magic, borderColor: colors.magic },
  today: { color: colors.heat, fontWeight: 600 },
  stepper: {
    display: "inline-flex",
    alignItems: "center",
    flexShrink: 0,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface1,
    borderRadius: 8,
    overflow: "hidden",
  },
  stepButton: {
    width: 32,
    height: 30,
    borderWidth: 0,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
    fontFamily: fonts.mono,
    fontSize: 15,
    opacity: { default: 1, ":disabled": 0.4 },
    cursor: { default: "pointer", ":disabled": "default" },
  },
  stepValue: {
    minWidth: 84,
    paddingInline: 6,
    textAlign: "center",
    fontFamily: fonts.mono,
    fontSize: 12.5,
    color: colors.ink,
  },
  count: { margin: 0, fontFamily: fonts.mono, fontSize: 13, color: colors.subtext },
  over: { color: colors.heat },
  actions: { display: "flex", justifyContent: "flex-end", flexWrap: "wrap", gap: 8 },
});
