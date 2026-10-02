import * as stylex from "@stylexjs/stylex";
import { copy, type DiaryEntryInput, type MealSlot, TRACKER_LIMITS } from "@cauldron/shared";
import { type FormEvent, useEffect, useState } from "react";
import { Button, Dialog, FormMessage, Input } from "../ui";
import { focusRing } from "../ui/controls";
import { colors, fonts } from "../../styles/tokens.stylex";
import { DescribeIt } from "./DescribeIt";
import { RecipePicker } from "./LogRecipe";
import { Recents } from "./Recents";
import { emptyDraft, type MacroDraft, MacroFields, readDraft } from "./MacroFields";

// What the diary's add button opens, for one meal slot: recents and
// favourites to log again in one tap (#116), describe it in words (#114),
// pick a recipe (#115), or quick add by numbers, the plain fallback.

const TABS = ["recents", "describe", "recipe", "quick"] as const;
type Tab = (typeof TABS)[number];

export function AddSheet({
  date,
  slot,
  onClose,
  onLog,
}: {
  date: string;
  slot: MealSlot | null;
  onClose: () => void;
  onLog: (inputs: ReadonlyArray<DiaryEntryInput>) => void;
}) {
  const slotName = slot === null ? "" : copy.week.slots[slot].text;
  return (
    <Dialog
      open={slot !== null}
      onClose={onClose}
      title={copy.tracker.entry.addTitle(slotName).text}
    >
      {slot === null ? null : (
        <Ways key={`${date}/${slot}`} date={date} slot={slot} onLog={onLog} />
      )}
    </Dialog>
  );
}

function Ways({
  date,
  slot,
  onLog,
}: {
  date: string;
  slot: MealSlot;
  onLog: (inputs: ReadonlyArray<DiaryEntryInput>) => void;
}) {
  const [tab, setTab] = useState<Tab>("recents");
  return (
    <div {...stylex.props(styles.sections)}>
      <div
        role="tablist"
        aria-label={copy.tracker.addTabs.label.text}
        {...stylex.props(styles.tabs)}
      >
        {TABS.map((t) => (
          <button
            key={t}
            type="button"
            role="tab"
            aria-selected={tab === t}
            onClick={() => setTab(t)}
            {...stylex.props(styles.tab, tab === t && styles.tabOn, focusRing.ring)}
          >
            {copy.tracker.addTabs[t].text}
          </button>
        ))}
      </div>
      <div role="tabpanel">
        {tab === "recents" ? (
          <Recents date={date} slot={slot} onLog={onLog} />
        ) : tab === "describe" ? (
          <DescribeIt date={date} slot={slot} onLog={onLog} />
        ) : tab === "recipe" ? (
          <RecipePicker date={date} slot={slot} onLog={onLog} />
        ) : (
          <QuickAdd date={date} slot={slot} onLog={onLog} />
        )}
      </div>
    </div>
  );
}

function QuickAdd({
  date,
  slot,
  onLog,
}: {
  date: string;
  slot: MealSlot;
  onLog: (inputs: ReadonlyArray<DiaryEntryInput>) => void;
}) {
  const [name, setName] = useState("");
  const [amount, setAmount] = useState("");
  const [draft, setDraft] = useState<MacroDraft>(emptyDraft);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => setError(null), [name, draft]);

  const submit = (e: FormEvent) => {
    e.preventDefault();
    const macros = readDraft(draft);
    if (name.trim() === "" || macros === null || macros.calories === null) {
      return setError(copy.validation.required.text);
    }
    onLog([
      {
        date,
        slot,
        name: name.trim(),
        amount: amount.trim() || null,
        servings: 1,
        macros,
        source: "manual",
      },
    ]);
  };

  return (
    <form onSubmit={submit} noValidate {...stylex.props(styles.form)}>
      <p {...stylex.props(styles.hint)}>{copy.tracker.entry.quickAddHint.text}</p>
      <div {...stylex.props(styles.row)}>
        <Input
          label={copy.tracker.entry.name.text}
          placeholder={copy.tracker.entry.namePlaceholder.text}
          value={name}
          maxLength={TRACKER_LIMITS.name}
          onChange={(e) => setName(e.target.value)}
        />
        <Input
          label={copy.tracker.entry.amount.text}
          placeholder={copy.tracker.entry.amountPlaceholder.text}
          value={amount}
          maxLength={TRACKER_LIMITS.amount}
          onChange={(e) => setAmount(e.target.value)}
          xstyle={styles.mono}
        />
      </div>
      <MacroFields draft={draft} onChange={setDraft} required />
      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      <div {...stylex.props(styles.actions)}>
        <Button type="submit">{copy.tracker.entry.log.text}</Button>
      </div>
    </form>
  );
}

const styles = stylex.create({
  sections: { display: "flex", flexDirection: "column", gap: 14 },
  tabs: {
    display: "flex",
    gap: 4,
    padding: 4,
    borderRadius: 10,
    backgroundColor: colors.base,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
  },
  tab: {
    flexGrow: 1,
    paddingBlock: 7,
    paddingInline: 10,
    borderRadius: 7,
    borderWidth: 0,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.subtext,
    fontFamily: fonts.ui,
    fontSize: 14,
    fontWeight: 500,
    cursor: "pointer",
  },
  tabOn: {
    backgroundColor: { default: colors.surface0, ":hover": colors.surface0 },
    color: colors.ink,
    fontWeight: 600,
  },
  form: { display: "flex", flexDirection: "column", gap: 12 },
  hint: { margin: 0, fontSize: 13, color: colors.subtext },
  row: {
    display: "grid",
    gridTemplateColumns: { default: "2fr 1fr", "@media (max-width: 480px)": "1fr" },
    gap: 10,
  },
  mono: { fontFamily: fonts.mono },
  actions: { display: "flex", justifyContent: "flex-end", gap: 8 },
});
