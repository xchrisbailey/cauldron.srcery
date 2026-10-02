import * as stylex from "@stylexjs/stylex";
import {
  addDays,
  copy,
  type DiaryEntry,
  type DiaryEntryUpdate,
  entryTotals,
  MACRO_KEYS,
  MEAL_SLOTS,
  type MealSlot,
  TRACKER_LIMITS,
} from "@cauldron/shared";
import { type FormEvent, useEffect, useState } from "react";
import { dayLabel } from "../../lib/dates";
import { Button, Dialog, FormMessage, Input, Select } from "../ui";
import { colors, fonts } from "../../styles/tokens.stylex";
import { draftOf, type MacroDraft, MacroFields, readDraft } from "./MacroFields";

// Changing a logged entry: servings, numbers, name, meal or day, or removing it.

const SERVING_STEP = 0.25;

export function EntrySheet({
  entry,
  today,
  onClose,
  onSave,
  onRemove,
}: {
  entry: DiaryEntry | null;
  today: string;
  onClose: () => void;
  onSave: (entry: DiaryEntry, change: DiaryEntryUpdate) => void;
  onRemove: (entry: DiaryEntry) => void;
}) {
  return (
    <Dialog open={entry !== null} onClose={onClose} title={entry?.name ?? ""}>
      {entry ? (
        <EntryForm key={entry.id} entry={entry} today={today} onSave={onSave} onRemove={onRemove} />
      ) : null}
    </Dialog>
  );
}

function EntryForm({
  entry,
  today,
  onSave,
  onRemove,
}: {
  entry: DiaryEntry;
  today: string;
  onSave: (entry: DiaryEntry, change: DiaryEntryUpdate) => void;
  onRemove: (entry: DiaryEntry) => void;
}) {
  const [name, setName] = useState(entry.name);
  const [amount, setAmount] = useState(entry.amount ?? "");
  const [servings, setServings] = useState(String(+entry.servings.toFixed(2)));
  const [slot, setSlot] = useState<MealSlot>(entry.slot);
  const [date, setDate] = useState(entry.date);
  const [draft, setDraft] = useState<MacroDraft>(draftOf(entry.macros));
  const [error, setError] = useState<string | null>(null);
  useEffect(() => setError(null), [name, servings, draft]);

  const servingsNumber = Number(servings);
  const servingsOk =
    servings.trim() !== "" &&
    Number.isFinite(servingsNumber) &&
    servingsNumber > 0 &&
    servingsNumber <= TRACKER_LIMITS.servings;
  const macros = readDraft(draft);
  const total = macros && servingsOk ? entryTotals({ macros, servings: servingsNumber }) : null;
  // A week either side of the entry's day, and today.
  const days = [
    ...new Set([...Array.from({ length: 15 }, (_, i) => addDays(entry.date, i - 7)), today]),
  ].sort();

  const save = (e: FormEvent) => {
    e.preventDefault();
    if (name.trim() === "" || !servingsOk || macros === null) {
      return setError(copy.validation.numberBetween(0, TRACKER_LIMITS.servings).text);
    }
    const changedMacros = MACRO_KEYS.some((k) => macros[k] !== entry.macros[k]);
    onSave(entry, {
      ...(name.trim() !== entry.name ? { name: name.trim() } : {}),
      ...((amount.trim() || null) !== entry.amount ? { amount: amount.trim() || null } : {}),
      ...(servingsNumber !== entry.servings ? { servings: servingsNumber } : {}),
      ...(slot !== entry.slot ? { slot } : {}),
      ...(date !== entry.date ? { date } : {}),
      ...(changedMacros ? { macros } : {}),
    });
  };

  const nudge = (by: number) => {
    const next = Math.max(
      SERVING_STEP,
      (Number.isFinite(servingsNumber) ? servingsNumber : 1) + by,
    );
    setServings(String(+next.toFixed(2)));
  };

  return (
    <form onSubmit={save} noValidate {...stylex.props(styles.form)}>
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
      {total ? (
        <p {...stylex.props(styles.total)}>
          {copy.tracker.entry.total.text}:{" "}
          <span {...stylex.props(styles.mono)}>
            {Math.round(total.calories).toLocaleString()} {copy.tracker.macros.calories.text} ·{" "}
            {Math.round(total.protein)}
            {copy.tracker.macros.grams.text} {copy.tracker.macros.protein.text} ·{" "}
            {Math.round(total.carbs)}
            {copy.tracker.macros.grams.text} {copy.tracker.macros.carbs.text} ·{" "}
            {Math.round(total.fat)}
            {copy.tracker.macros.grams.text} {copy.tracker.macros.fat.text}
          </span>
        </p>
      ) : null}
      <div {...stylex.props(styles.row)}>
        <Input
          label={copy.tracker.entry.name.text}
          value={name}
          maxLength={TRACKER_LIMITS.name}
          onChange={(e) => setName(e.target.value)}
        />
        <Input
          label={copy.tracker.entry.amount.text}
          value={amount}
          maxLength={TRACKER_LIMITS.amount}
          onChange={(e) => setAmount(e.target.value)}
          xstyle={styles.mono}
        />
      </div>
      <fieldset {...stylex.props(styles.fieldset)}>
        <legend {...stylex.props(styles.legend)}>{copy.tracker.entry.perServing.text}</legend>
        <MacroFields draft={draft} onChange={setDraft} />
      </fieldset>
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
        <Select
          label={copy.tracker.entry.day.text}
          value={date}
          onChange={(e) => setDate(e.target.value)}
        >
          {days.map((d) => (
            <option key={d} value={d}>
              {dayLabel(d, "short")}
            </option>
          ))}
        </Select>
      </div>
      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      <div {...stylex.props(styles.actions)}>
        <Button variant="danger" onClick={() => onRemove(entry)}>
          {copy.tracker.entry.remove.text}
        </Button>
        <Button type="submit">{copy.tracker.entry.save.text}</Button>
      </div>
    </form>
  );
}

const styles = stylex.create({
  form: { display: "flex", flexDirection: "column", gap: 12 },
  servingsRow: { display: "flex", alignItems: "flex-end", gap: 8 },
  servings: { fontFamily: fonts.mono, textAlign: "center", fontVariantNumeric: "tabular-nums" },
  total: { margin: 0, fontSize: 13, color: colors.subtext },
  mono: { fontFamily: fonts.mono, color: colors.ink, fontVariantNumeric: "tabular-nums" },
  row: {
    display: "grid",
    gridTemplateColumns: { default: "1fr 1fr", "@media (max-width: 480px)": "1fr" },
    gap: 10,
  },
  fieldset: {
    margin: 0,
    padding: 0,
    borderWidth: 0,
    display: "flex",
    flexDirection: "column",
    gap: 8,
  },
  legend: { padding: 0, marginBottom: 8, fontSize: 13, fontWeight: 600, color: colors.subtext },
  actions: { display: "flex", justifyContent: "space-between", gap: 8 },
});
