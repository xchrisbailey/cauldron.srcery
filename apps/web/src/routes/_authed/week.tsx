import * as stylex from "@stylexjs/stylex";
import {
  addDays,
  copy,
  formatTimer,
  isRealDate,
  MEAL_SLOTS,
  type MealSlot,
  noMacros,
  PLAN_LIMITS,
  type PlanEntry,
  type PlanEntryUpdate,
  servingsOf,
  startOfWeek,
  tallyMacros,
  weekDays,
  type WeekStartDay,
} from "@cauldron/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { type DragEvent, type FormEvent, useEffect, useMemo, useState } from "react";
import { BagGlyph, PlusGlyph } from "../../components/glyphs";
import { MacroTally } from "../../components/MacroTally";
import { type Spreading, SpreadDialog } from "../../components/SpreadDialog";
import { PickMealDialog, stirRecipe, useRecipeSearch } from "../../components/StirIn";
import { WeekRange } from "../../components/WeekRange";
import {
  Button,
  ButtonLink,
  Dialog,
  EmptyState,
  IconButton,
  Input,
  PageHeader,
  Select,
  Skeleton,
  useToast,
} from "../../components/ui";
import { control, focusRing } from "../../components/ui/controls";
import { dayLabel, dayOfMonth, weekdayName, weekRangeLabel } from "../../lib/dates";
import {
  clearWeek,
  copyWeek,
  inSlot,
  isPending,
  planKeys,
  settlePlan,
  dropAt,
  dropMove,
  planMutationKey,
  savedWeekStartDay,
  useWeekStartDay,
  weekQuery,
} from "../../lib/plan";
import { gatherQuery, summarize } from "../../lib/gather";
import { localToday } from "../../lib/recipes";
import { type StirRecipe, usePlanWrites } from "../../lib/use-plan";
import { colors, fonts } from "../../styles/tokens.stylex";

// The week (#18): a seven-day calendar of breakfast, lunch, dinner and snack,
// with the week's calories and macros on top and the chosen day's beside them.
// A recipe stirred in can feed several days. Desktop has a recipe panel to
// drag from; a phone shows one day at a time. Every change shows at once and
// rolls back if the API refuses it.

export const Route = createFileRoute("/_authed/week")({
  validateSearch: (search: Record<string, unknown>): { week?: string } =>
    typeof search.week === "string" && isRealDate(search.week) ? { week: search.week } : {},
  component: Week,
});

const RECIPE_TYPE = "application/x-cauldron-recipe";
const ENTRY_TYPE = "application/x-cauldron-entry";

const num = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) ? value : null;

/** A recipe dragged in from the panel. Anything else with the same type is ignored. */
const readRecipe = (data: string): StirRecipe | null => {
  if (data === "") return null;
  try {
    const value: unknown = JSON.parse(data);
    if (
      typeof value === "object" &&
      value !== null &&
      "id" in value &&
      "title" in value &&
      typeof value.id === "string" &&
      typeof value.title === "string"
    ) {
      const v = value as Partial<StirRecipe>;
      return {
        id: v.id!,
        title: v.title!,
        servings: typeof v.servings === "number" ? v.servings : null,
        totalMinutes: typeof v.totalMinutes === "number" ? v.totalMinutes : null,
        macros:
          typeof v.macros === "object" && v.macros !== null
            ? {
                calories: num(v.macros.calories),
                protein: num(v.macros.protein),
                carbs: num(v.macros.carbs),
                fat: num(v.macros.fat),
              }
            : noMacros,
      };
    }
  } catch {
    // Not ours.
  }
  return null;
};

type Target = { date: string; slot: MealSlot };

function Week() {
  // Today and the first day of the week are the viewer's own, so they're only
  // known in the browser.
  const [viewer, setViewer] = useState<{ today: string; startsOn: WeekStartDay } | null>(null);
  useEffect(() => setViewer({ today: localToday(), startsOn: savedWeekStartDay() }), []);
  if (viewer === null) return <WeekSkeleton />;
  return <Planner today={viewer.today} initialStartsOn={viewer.startsOn} />;
}

function WeekSkeleton() {
  return (
    <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.page)}>
      <Skeleton height={40} width="40%" />
      <Skeleton height={320} />
    </div>
  );
}

function Planner({ today, initialStartsOn }: { today: string; initialStartsOn: WeekStartDay }) {
  const search = Route.useSearch();
  const navigate = useNavigate({ from: Route.fullPath });
  const queryClient = useQueryClient();
  const toast = useToast();
  const [startsOn, setStartsOn] = useWeekStartDay(initialStartsOn);
  const start = startOfWeek(search.week ?? today, startsOn);
  const thisWeek = startOfWeek(today, startsOn);
  const days = useMemo(() => weekDays(start), [start]);
  const week = useQuery(weekQuery(start));
  const writes = usePlanWrites(startsOn);

  const [picking, setPicking] = useState<Target | null>(null);
  const [spreading, setSpreading] = useState<Spreading | null>(null);
  const [editing, setEditing] = useState<PlanEntry | null>(null);
  const [clearing, setClearing] = useState(false);
  /** The day whose macros show beside the week's; on a phone, the day shown. */
  const [chosen, setChosen] = useState<string | null>(null);
  const chosenDay = chosen !== null && days.includes(chosen) ? chosen : null;
  const phoneDay = chosenDay ?? (days.includes(today) ? today : days[0]!);

  const goTo = (weekStart: string) =>
    void navigate({ search: weekStart === thisWeek ? {} : { week: weekStart } });

  const copyLast = useMutation({
    mutationKey: planMutationKey,
    mutationFn: () => copyWeek(addDays(start, -7), start),
    onMutate: () => queryClient.cancelQueries({ queryKey: planKeys.week(start) }),
    onSuccess: (entries) => {
      queryClient.setQueryData(planKeys.week(start), entries);
      toast(
        entries.length > (week.data?.length ?? 0)
          ? copy.week.copiedLastWeek.text
          : copy.week.nothingToCopy.text,
      );
    },
    onError: () => toast(copy.week.couldntSave.text, "error"),
    onSettled: () => settlePlan(queryClient),
  });

  const clear = useMutation({
    mutationKey: planMutationKey,
    mutationFn: () => clearWeek(start),
    onMutate: async () => {
      setClearing(false);
      await queryClient.cancelQueries({ queryKey: planKeys.week(start) });
      queryClient.setQueryData(planKeys.week(start), []);
    },
    onSuccess: () => toast(copy.week.cleared.text),
    onError: () => toast(copy.week.couldntSave.text, "error"),
    onSettled: () => settlePlan(queryClient),
  });

  /** A recipe goes through the days picker, so its servings can feed more than one day. */
  const stir = (target: Target, recipe: StirRecipe, position?: number) =>
    setSpreading({ ...target, recipe, ...(position === undefined ? {} : { position }) });

  const pick = (choice: { recipe: StirRecipe } | { title: string }) => {
    if (!picking) return;
    if ("recipe" in choice) stir(picking, choice.recipe);
    else writes.stir({ ...picking, title: choice.title }, null);
    setPicking(null);
  };

  const entries = useMemo(() => week.data ?? [], [week.data]);
  const tallies = useMemo(
    () => new Map(days.map((day) => [day, tallyMacros(entries.filter((e) => e.date === day))])),
    [days, entries],
  );
  const weekTally = useMemo(() => tallyMacros(entries), [entries]);
  const daysPlanned = [...tallies.values()].filter((t) => t.totals.calories > 0).length;
  const toggleDay = (day: string) => setChosen((current) => (current === day ? null : day));

  /** A recipe or a meal dropped on a slot, before `before` when it landed on one. */
  const drop = (e: DragEvent, target: Target, before?: PlanEntry) => {
    e.preventDefault();
    e.stopPropagation();
    const recipe = readRecipe(e.dataTransfer.getData(RECIPE_TYPE));
    if (recipe) {
      stir(target, recipe, dropAt(entries, target, before?.id));
      return;
    }
    const entryId = e.dataTransfer.getData(ENTRY_TYPE);
    const moving = entries.find((s) => s.id === entryId);
    if (!moving || isPending(moving)) return;
    const update = dropMove(entries, entryId, target, before?.id);
    if (update) writes.update.mutate({ entry: moving, update });
  };

  const slotProps = (target: Target) => ({
    onDragOver: (e: DragEvent) => {
      if (e.dataTransfer.types.includes(RECIPE_TYPE) || e.dataTransfer.types.includes(ENTRY_TYPE)) {
        e.preventDefault();
        e.dataTransfer.dropEffect = e.dataTransfer.types.includes(RECIPE_TYPE) ? "copy" : "move";
      }
    },
    onDrop: (e: DragEvent) => drop(e, target),
  });

  const card = (entry: PlanEntry) => (
    <EntryCard
      key={entry.id}
      entry={entry}
      past={entry.date < today}
      today={entry.date === today}
      onOpen={() => !isPending(entry) && setEditing(entry)}
      onDrop={(e) => drop(e, { date: entry.date, slot: entry.slot }, entry)}
    />
  );

  return (
    <div {...stylex.props(styles.page)}>
      <PageHeader
        title={copy.week.title.text}
        actions={
          <>
            <Button
              variant="secondary"
              onClick={() => copyLast.mutate()}
              disabled={copyLast.isPending || week.isPending}
            >
              {copy.week.copyLastWeek.text}
            </Button>
            <Button
              variant="ghost"
              onClick={() => setClearing(true)}
              disabled={entries.length === 0}
            >
              {copy.week.clearWeek.text}
            </Button>
          </>
        }
      />

      <WeekRange start={start} thisWeek={thisWeek} onGo={goTo} />

      {week.isError ? (
        <EmptyState
          message={copy.week.couldntLoad.text}
          actions={
            <Button variant="secondary" onClick={() => void week.refetch()}>
              {copy.week.retry.text}
            </Button>
          }
        />
      ) : week.isPending ? (
        <Skeleton height={320} />
      ) : (
        <>
          <MacroTally
            week={weekTally}
            daysPlanned={daysPlanned}
            day={chosenDay}
            dayTally={chosenDay === null ? null : tallies.get(chosenDay)!}
            onClearDay={() => setChosen(null)}
          />

          {entries.length === 0 ? (
            <p {...stylex.props(styles.empty)}>{copy.week.empty.text}</p>
          ) : null}

          <div {...stylex.props(styles.desk)}>
            <div {...stylex.props(styles.calendar)} aria-label={weekRangeLabel(start)} role="group">
              {days.map((day) => {
                const tally = tallies.get(day)!;
                const label = dayLabel(day, "long");
                return (
                  <section
                    key={day}
                    aria-label={label}
                    {...stylex.props(
                      styles.dayCol,
                      day === today && styles.dayColToday,
                      day === chosenDay && styles.dayColOn,
                    )}
                  >
                    <button
                      type="button"
                      aria-pressed={day === chosenDay}
                      aria-current={day === today ? "date" : undefined}
                      aria-label={copy.week.tally.showDay(label).text}
                      onClick={() => toggleDay(day)}
                      {...stylex.props(styles.dayHead, focusRing.ring)}
                    >
                      <span {...stylex.props(styles.dayName, day === today && styles.dayToday)}>
                        {weekdayName(day, "short")}
                      </span>
                      <span {...stylex.props(styles.dayNumber, day === today && styles.dayToday)}>
                        {dayOfMonth(day)}
                      </span>
                      <span {...stylex.props(styles.dayKcal)}>
                        {tally.totals.calories > 0
                          ? `${Math.round(tally.totals.calories).toLocaleString()} ${copy.week.tally.macros.calories.text}`
                          : "\u00a0"}
                      </span>
                    </button>
                    {MEAL_SLOTS.map((slot) => {
                      const here = inSlot(entries, day, slot);
                      return (
                        <div
                          key={slot}
                          {...slotProps({ date: day, slot })}
                          {...stylex.props(styles.cell)}
                        >
                          <span {...stylex.props(styles.slotLabel)}>
                            {copy.week.slots[slot].text}
                          </span>
                          {here.map(card)}
                          <button
                            type="button"
                            aria-label={
                              copy.week.stirInto(dayLabel(day, "long"), copy.week.slots[slot].text)
                                .text
                            }
                            onClick={() => setPicking({ date: day, slot })}
                            {...stylex.props(
                              styles.add,
                              here.length > 0 && styles.addSmall,
                              day < today && styles.past,
                              focusRing.ring,
                            )}
                          >
                            <PlusGlyph />
                          </button>
                        </div>
                      );
                    })}
                  </section>
                );
              })}
            </div>
            <RecipePanel />
          </div>

          <div {...stylex.props(styles.phone)}>
            <div role="group" aria-label={copy.week.days.text} {...stylex.props(styles.dayTabs)}>
              {days.map((day) => {
                const kcal = tallies.get(day)!.totals.calories;
                return (
                  <button
                    key={day}
                    type="button"
                    aria-pressed={day === phoneDay}
                    aria-current={day === today ? "date" : undefined}
                    aria-label={dayLabel(day, "long")}
                    onClick={() => setChosen(day)}
                    {...stylex.props(
                      styles.dayTab,
                      day === today && styles.dayTabToday,
                      day === phoneDay && styles.dayTabOn,
                      focusRing.ring,
                    )}
                  >
                    <span>{weekdayName(day, "short")}</span>
                    <span {...stylex.props(styles.dayTabNumber)}>{dayOfMonth(day)}</span>
                    <span aria-hidden="true" {...stylex.props(styles.dayTabKcal)}>
                      {kcal > 0 ? Math.round(kcal).toLocaleString() : "·"}
                    </span>
                  </button>
                );
              })}
            </div>
            <h2 {...stylex.props(styles.dayTitle, phoneDay === today && styles.dayToday)}>
              {weekdayName(phoneDay, "long")}
            </h2>
            <div {...stylex.props(styles.dayList)}>
              {MEAL_SLOTS.map((slot) => (
                <section key={slot} {...stylex.props(styles.daySlot)}>
                  <div {...stylex.props(styles.daySlotHead)}>
                    <h3 {...stylex.props(styles.slotHead)}>{copy.week.slots[slot].text}</h3>
                    <IconButton
                      label={
                        copy.week.stirInto(dayLabel(phoneDay, "long"), copy.week.slots[slot].text)
                          .text
                      }
                      onClick={() => setPicking({ date: phoneDay, slot })}
                    >
                      <PlusGlyph />
                    </IconButton>
                  </div>
                  {inSlot(entries, phoneDay, slot).map(card)}
                </section>
              ))}
            </div>
          </div>
        </>
      )}

      <GatherBar start={start} thisWeek={thisWeek} />

      <label {...stylex.props(styles.startsOn)}>
        {copy.week.weekStarts.text}
        <select
          value={startsOn}
          onChange={(e) => setStartsOn(e.target.value === "0" ? 0 : 1)}
          {...stylex.props(control.field, control.select, styles.startsOnSelect)}
        >
          <option value="1">{copy.week.monday.text}</option>
          <option value="0">{copy.week.sunday.text}</option>
        </select>
      </label>

      <PickMealDialog target={picking} onClose={() => setPicking(null)} onPick={pick} />
      <SpreadDialog
        spreading={spreading}
        days={days}
        today={today}
        onClose={() => setSpreading(null)}
        onStir={(inputs, recipe) => {
          setSpreading(null);
          writes.spread(inputs, recipe);
        }}
      />
      <EntryDialog
        entry={editing}
        days={Array.from({ length: 21 }, (_, i) => addDays(start, i - 7))}
        slotSize={editing ? inSlot(entries, editing.date, editing.slot).length : 0}
        onClose={() => setEditing(null)}
        onSave={(entry, update) => {
          setEditing(null);
          if (Object.keys(update).length > 0) writes.update.mutate({ entry, update });
        }}
        onRemove={(entry) => {
          setEditing(null);
          writes.remove.mutate(entry);
        }}
      />
      <Dialog open={clearing} onClose={() => setClearing(false)} title={copy.week.clearWeek.text}>
        <p {...stylex.props(styles.dialogText)}>
          {copy.week.clearConfirm(weekRangeLabel(start)).text}
        </p>
        <div {...stylex.props(styles.dialogActions)}>
          <Button variant="secondary" data-autofocus onClick={() => setClearing(false)}>
            {copy.week.cancel.text}
          </Button>
          <Button variant="danger" onClick={() => clear.mutate()}>
            {copy.week.clearWeek.text}
          </Button>
        </div>
      </Dialog>
    </div>
  );
}

function EntryCard({
  entry,
  past,
  today,
  onOpen,
  onDrop,
}: {
  entry: PlanEntry;
  past: boolean;
  today: boolean;
  onOpen: () => void;
  onDrop: (e: DragEvent) => void;
}) {
  const minutes = entry.recipe?.totalMinutes ?? null;
  const servings = entry.servings ?? entry.recipe?.servings ?? null;
  const calories = entry.recipe?.macros.calories ?? null;
  const detail = entry.brewed
    ? copy.week.brewed.text
    : entry.recipe === null
      ? null
      : [
          minutes ? formatTimer(minutes * 60) : null,
          servings ? copy.week.spread.servingsOn(servings).text : null,
          calories === null
            ? null
            : `${Math.round(calories * servingsOf(entry)).toLocaleString()} ${copy.week.tally.macros.calories.text}`,
        ]
          .filter(Boolean)
          .join(" · ") || null;
  // Firefox won't start a drag from a <button>, so the wrapper is what drags.
  return (
    <div
      draggable={!isPending(entry)}
      onDragStart={(e) => {
        e.dataTransfer.setData(ENTRY_TYPE, entry.id);
        e.dataTransfer.effectAllowed = "move";
      }}
      onDragOver={(e) => {
        if (
          e.dataTransfer.types.includes(RECIPE_TYPE) ||
          e.dataTransfer.types.includes(ENTRY_TYPE)
        ) {
          e.preventDefault();
        }
      }}
      onDrop={onDrop}
      {...stylex.props(styles.entryWrap)}
    >
      <button
        type="button"
        onClick={onOpen}
        {...stylex.props(
          styles.entry,
          entry.recipe === null && styles.entryText,
          today && styles.entryToday,
          past && styles.past,
          isPending(entry) && styles.pending,
          focusRing.ring,
        )}
      >
        <span>{entry.recipe?.title ?? entry.title}</span>
        {detail ? <span {...stylex.props(styles.entryDetail)}>{detail}</span> : null}
      </button>
    </div>
  );
}

/** The week's Gather list in a line, with the way to it. */
function GatherBar({ start, thisWeek }: { start: string; thisWeek: string }) {
  const list = useQuery(gatherQuery(start));
  if (!list.data || list.data.items.length === 0) return null;
  const counts = summarize(list.data);
  return (
    <div {...stylex.props(styles.gatherBar)}>
      <span aria-hidden="true" {...stylex.props(styles.gatherGlyph)}>
        <BagGlyph />
      </span>
      <p {...stylex.props(styles.gatherText)}>
        {copy.gather.summary(counts.items, counts.recipes).text}
        {counts.inPantry > 0 ? ` ${copy.gather.inPantryCount(counts.inPantry).text}` : ""}
      </p>
      <ButtonLink
        to="/gather"
        search={start === thisWeek ? {} : { week: start }}
        variant="secondary"
      >
        {copy.gather.gather.text}
      </ButtonLink>
    </div>
  );
}

/** Desktop only: search the recipe box and drag a recipe onto a meal. */
function RecipePanel() {
  const [text, setText] = useState("");
  const { recipes } = useRecipeSearch(text);
  return (
    <aside aria-label={copy.week.recipesPanel.text} {...stylex.props(styles.panel)}>
      <h2 {...stylex.props(styles.slotHead)}>{copy.week.recipesPanel.text}</h2>
      <input
        type="search"
        aria-label={copy.week.searchRecipes.text}
        placeholder={copy.week.searchRecipes.text}
        autoComplete="off"
        value={text}
        onChange={(e) => setText(e.target.value)}
        {...stylex.props(control.field, styles.panelSearch)}
      />
      <p {...stylex.props(styles.hint)}>{copy.week.dragHint.text}</p>
      <ul {...stylex.props(styles.panelList)}>
        {recipes.map((recipe) => (
          <li
            key={recipe.id}
            draggable
            onDragStart={(e) => {
              e.dataTransfer.setData(RECIPE_TYPE, JSON.stringify(stirRecipe(recipe)));
              e.dataTransfer.effectAllowed = "copy";
            }}
            {...stylex.props(styles.panelItem)}
          >
            {recipe.title}
          </li>
        ))}
      </ul>
    </aside>
  );
}

/** Change one meal: servings, day and meal (the keyboard and phone way to move it), or remove it. */
function EntryDialog({
  entry,
  days,
  slotSize,
  onClose,
  onSave,
  onRemove,
}: {
  entry: PlanEntry | null;
  /** Days it can move to: this week and the weeks either side. */
  days: ReadonlyArray<string>;
  /** Meals in the entry's slot, for moving it up or down. */
  slotSize: number;
  onClose: () => void;
  onSave: (entry: PlanEntry, update: PlanEntryUpdate) => void;
  onRemove: (entry: PlanEntry) => void;
}) {
  const [date, setDate] = useState("");
  const [slot, setSlot] = useState<MealSlot>("dinner");
  const [servings, setServings] = useState("");
  const [title, setTitle] = useState("");
  useEffect(() => {
    if (!entry) return;
    setDate(entry.date);
    setSlot(entry.slot);
    setServings(entry.servings === null ? "" : String(entry.servings));
    setTitle(entry.title);
  }, [entry]);

  const save = (e: FormEvent) => {
    e.preventDefault();
    if (!entry) return;
    const nextServings = servings === "" ? null : Number(servings);
    onSave(entry, {
      ...(date !== entry.date ? { date } : {}),
      ...(slot !== entry.slot ? { slot } : {}),
      ...(nextServings !== entry.servings ? { servings: nextServings } : {}),
      ...(entry.recipe === null && title.trim() !== "" && title.trim() !== entry.title
        ? { title: title.trim() }
        : {}),
    });
  };

  const name = entry ? (entry.recipe?.title ?? entry.title) : "";
  const recipeServings = entry?.recipe?.servings ?? null;
  const choices = Array.from({ length: 24 }, (_, i) => i + 1);
  /** Reorder within the slot: the keyboard and phone way to do what dragging does. */
  const shift = (by: -1 | 1) => entry && onSave(entry, { position: entry.position + by });

  return (
    <Dialog open={entry !== null} onClose={onClose} title={name}>
      {entry ? (
        <form onSubmit={save} {...stylex.props(styles.form)}>
          {entry.recipe === null ? (
            <Input
              label={copy.week.meal.text}
              value={title}
              maxLength={PLAN_LIMITS.title}
              onChange={(e) => setTitle(e.target.value)}
            />
          ) : (
            <Select
              label={copy.week.servings.text}
              value={servings}
              onChange={(e) => setServings(e.target.value)}
            >
              <option value="">{copy.week.sameServings(recipeServings).text}</option>
              {choices.map((n) => (
                <option key={n} value={String(n)}>
                  {n}
                </option>
              ))}
            </Select>
          )}
          <div {...stylex.props(styles.formRow)}>
            <Select
              label={copy.week.day.text}
              value={date}
              onChange={(e) => setDate(e.target.value)}
            >
              {days.map((day) => (
                <option key={day} value={day}>
                  {dayLabel(day, "long")}
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
          </div>
          {slotSize > 1 ? (
            <div {...stylex.props(styles.reorder)}>
              <Button variant="secondary" onClick={() => shift(-1)} disabled={entry.position === 0}>
                {copy.week.moveUp.text}
              </Button>
              <Button
                variant="secondary"
                onClick={() => shift(1)}
                disabled={entry.position >= slotSize - 1}
              >
                {copy.week.moveDown.text}
              </Button>
            </div>
          ) : null}
          <div {...stylex.props(styles.dialogActions)}>
            {entry.recipe ? (
              <Link
                to="/recipes/$id"
                params={{ id: entry.recipe.id }}
                {...stylex.props(styles.openLink, focusRing.ring)}
              >
                {copy.week.open.text}
              </Link>
            ) : null}
            <Button variant="danger" onClick={() => onRemove(entry)}>
              {copy.week.remove.text}
            </Button>
            <Button type="submit">{copy.week.save.text}</Button>
          </div>
        </form>
      ) : null}
    </Dialog>
  );
}

const phone = "@media (max-width: 767px)";
const wide = "@media (min-width: 1280px)";

const styles = stylex.create({
  page: { display: "flex", flexDirection: "column", gap: 16 },
  empty: { margin: 0, color: colors.subtext },
  desk: {
    display: { default: "grid", [phone]: "none" },
    gridTemplateColumns: { default: "minmax(0, 1fr)", [wide]: "minmax(0, 1fr) 220px" },
    gap: 20,
    alignItems: "start",
  },
  // Seven day columns sharing one set of rows (the day head, then each meal),
  // so a meal lines up across the week however full the days are.
  calendar: {
    display: "grid",
    gridTemplateColumns: "repeat(7, minmax(0, 1fr))",
    gridTemplateRows: "auto repeat(4, auto)",
    columnGap: 6,
    minWidth: 0,
  },
  dayCol: {
    display: "grid",
    gridRow: "span 5",
    gridTemplateRows: "subgrid",
    rowGap: 4,
    minWidth: 0,
    paddingBlockEnd: 6,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "transparent",
  },
  dayColToday: { borderColor: `color-mix(in srgb, ${colors.heat} 30%, transparent)` },
  dayColOn: {
    borderColor: colors.magic,
    backgroundColor: `color-mix(in srgb, ${colors.magic} 6%, transparent)`,
  },
  dayHead: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "baseline",
    columnGap: 6,
    rowGap: 2,
    paddingBlock: 6,
    paddingInline: 6,
    borderWidth: 0,
    borderRadius: 11,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.subtext,
    fontFamily: fonts.ui,
    fontSize: 12.5,
    textAlign: "start",
    cursor: "pointer",
  },
  dayName: { fontWeight: 500 },
  dayNumber: { fontFamily: fonts.mono, fontSize: 11.5, color: colors.overlay0 },
  dayToday: { color: colors.heat, fontWeight: 600 },
  dayKcal: {
    flexBasis: "100%",
    fontFamily: fonts.mono,
    fontSize: 11,
    color: colors.overlay1,
    whiteSpace: "nowrap",
    overflow: "hidden",
    textOverflow: "ellipsis",
  },
  slotLabel: {
    paddingInline: 4,
    fontFamily: fonts.mono,
    fontSize: 9.5,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.overlay0,
  },
  slotHead: {
    margin: 0,
    paddingTop: 10,
    fontFamily: fonts.mono,
    fontSize: 10.5,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  cell: {
    display: "flex",
    flexDirection: "column",
    gap: 4,
    minHeight: 66,
    minWidth: 0,
    paddingInline: 4,
  },
  entry: {
    display: "flex",
    flexDirection: "column",
    justifyContent: "space-between",
    alignItems: "stretch",
    gap: 6,
    minHeight: { default: 66, [phone]: 56 },
    paddingBlock: { default: 8, [phone]: 12 },
    paddingInline: { default: 9, [phone]: 14 },
    borderRadius: { default: 9, [phone]: 14 },
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
    color: colors.ink,
    fontFamily: fonts.ui,
    fontSize: { default: 12.5, [phone]: 15 },
    fontWeight: { default: 400, [phone]: 600 },
    lineHeight: 1.35,
    textAlign: "start",
    cursor: "pointer",
    overflowWrap: "anywhere",
  },
  entryText: { backgroundColor: "transparent", borderStyle: "dashed", color: colors.subtext },
  entryToday: { borderColor: `color-mix(in srgb, ${colors.heat} 55%, transparent)` },
  entryWrap: { display: "flex", flexDirection: "column" },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
  entryDetail: { fontFamily: fonts.mono, fontSize: 11, fontWeight: 400, color: colors.overlay1 },
  past: { opacity: 0.55 },
  pending: { opacity: 0.6, cursor: "progress" },
  add: {
    display: "grid",
    placeItems: "center",
    flexGrow: 1,
    minHeight: 66,
    borderWidth: 1,
    borderStyle: "dashed",
    borderColor: colors.surface0,
    borderRadius: 9,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.overlay0,
    cursor: "pointer",
  },
  addSmall: { flexGrow: 0, minHeight: 28 },
  panel: {
    display: { default: "none", [wide]: "flex" },
    flexDirection: "column",
    gap: 8,
    position: "sticky",
    top: 16,
    maxHeight: "calc(100dvh - 120px)",
  },
  panelSearch: { paddingBlock: 7, fontSize: 14 },
  hint: { margin: 0, fontSize: 12.5, color: colors.subtext },
  panelList: {
    listStyle: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
    gap: 4,
    overflowY: "auto",
  },
  panelItem: {
    paddingBlock: 7,
    paddingInline: 10,
    borderRadius: 8,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
    fontSize: 13.5,
    cursor: "grab",
  },
  phone: { display: { default: "none", [phone]: "flex" }, flexDirection: "column", gap: 12 },
  dayTabs: {
    display: "grid",
    gridTemplateColumns: "repeat(7, minmax(0, 1fr))",
    gap: 4,
  },
  dayTab: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 2,
    minHeight: 52,
    paddingBlock: 6,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "transparent",
    borderRadius: 10,
    backgroundColor: "transparent",
    color: colors.subtext,
    fontFamily: fonts.ui,
    fontSize: 12,
    cursor: "pointer",
  },
  dayTabToday: { color: colors.heat, fontWeight: 600 },
  dayTabOn: { backgroundColor: colors.mantle, borderColor: colors.surface1, color: colors.ink },
  dayTabNumber: { fontFamily: fonts.mono, fontSize: 14 },
  dayTabKcal: { fontFamily: fonts.mono, fontSize: 9.5, color: colors.overlay1 },
  dayTitle: { margin: 0, fontSize: 28, fontWeight: 800, letterSpacing: "-0.03em" },
  dayList: { display: "flex", flexDirection: "column", gap: 14 },
  daySlot: { display: "flex", flexDirection: "column", gap: 8 },
  daySlotHead: { display: "flex", alignItems: "center", justifyContent: "space-between" },
  gatherBar: {
    display: "flex",
    alignItems: "center",
    gap: 14,
    paddingBlock: 12,
    paddingInline: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
  },
  gatherGlyph: { display: "flex", color: colors.magic },
  gatherText: { margin: 0, flexGrow: 1, fontSize: 13.5, color: colors.subtext },
  startsOn: {
    display: "flex",
    alignItems: "center",
    gap: 10,
    marginTop: 12,
    fontSize: 13.5,
    color: colors.subtext,
  },
  startsOnSelect: { width: "auto", paddingBlock: 6, fontSize: 13.5 },
  dialogText: { margin: 0, color: colors.subtext },
  dialogActions: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    justifyContent: "flex-end",
    gap: 8,
  },
  form: { display: "flex", flexDirection: "column", gap: 14 },
  reorder: { display: "flex", gap: 8 },
  formRow: {
    display: "grid",
    gridTemplateColumns: { default: "1fr 1fr", [phone]: "1fr" },
    gap: 12,
  },
  openLink: {
    marginInlineEnd: "auto",
    color: colors.ink,
    fontSize: 14,
    borderRadius: 4,
    textDecorationLine: "underline",
    textDecorationColor: colors.magic,
    textUnderlineOffset: 3,
  },
});
