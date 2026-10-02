import * as stylex from "@stylexjs/stylex";
import { copy, type DiaryEntryInput, type MealSlot, TRACKER_LIMITS } from "@cauldron/shared";
import { type FormEvent, useEffect, useState } from "react";
import { Button, Dialog, FormMessage, Input } from "../ui";
import { colors, fonts } from "../../styles/tokens.stylex";
import { DescribeIt } from "./DescribeIt";
import { emptyDraft, type MacroDraft, MacroFields, readDraft } from "./MacroFields";

// What the diary's add button opens, for one meal slot. Quick add by numbers
// is the plain fallback; describing a meal (#114), logging a recipe (#115)
// and recents (#116) sit above it.

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
        <div key={`${date}/${slot}`} {...stylex.props(styles.sections)}>
          <DescribeIt date={date} slot={slot} onLog={onLog} />
          <details {...stylex.props(styles.more)}>
            <summary {...stylex.props(styles.summary)}>{copy.tracker.entry.quickAdd.text}</summary>
            <QuickAdd date={date} slot={slot} onLog={onLog} />
          </details>
        </div>
      )}
    </Dialog>
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
  sections: { display: "flex", flexDirection: "column", gap: 16 },
  more: {
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopStyle: "solid",
    borderTopColor: colors.surface0,
  },
  summary: { cursor: "pointer", fontSize: 14, fontWeight: 650, marginBottom: 8 },
  form: { display: "flex", flexDirection: "column", gap: 12, paddingTop: 8 },
  hint: { margin: 0, fontSize: 13, color: colors.subtext },
  row: {
    display: "grid",
    gridTemplateColumns: { default: "2fr 1fr", "@media (max-width: 480px)": "1fr" },
    gap: 10,
  },
  mono: { fontFamily: fonts.mono },
  actions: { display: "flex", justifyContent: "flex-end", gap: 8 },
});
