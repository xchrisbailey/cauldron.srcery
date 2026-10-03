import * as stylex from "@stylexjs/stylex";
import {
  copy,
  type DescribedItem,
  type DiaryEntryInput,
  dayTotals,
  MEAL_DESCRIPTION_MAX,
  type MealSlot,
  TRACKER_LIMITS,
} from "@cauldron/shared";
import { useMutation } from "@tanstack/react-query";
import { type FormEvent, useState } from "react";
import { callApi } from "../../lib/api";
import { messageOr } from "../../lib/api-failure";
import { colors, fonts } from "../../styles/tokens.stylex";
import { CloseGlyph } from "../glyphs";
import { Button, FormMessage, IconButton, Input, Textarea } from "../ui";
import { draftOf, type MacroDraft, MacroFields, readDraft } from "./MacroFields";

// Describe it (#114): type what you ate, the model splits it into foods with
// estimated numbers, and each can be changed or dropped before anything is
// logged. A failure keeps the text, so it can be tried again or typed in.

interface Row {
  readonly key: string;
  readonly name: string;
  readonly amount: string;
  readonly draft: MacroDraft;
}

const toRow = (item: DescribedItem, i: number): Row => ({
  key: `${i}-${item.name}`,
  name: item.name,
  amount: item.amount ?? "",
  draft: draftOf(item.macros),
});

const whole = (n: number) => Math.round(n).toLocaleString();

export function DescribeIt({
  date,
  slot,
  onLog,
}: {
  date: string;
  slot: MealSlot;
  onLog: (inputs: ReadonlyArray<DiaryEntryInput>) => void;
}) {
  const [text, setText] = useState("");
  const [rows, setRows] = useState<ReadonlyArray<Row> | null>(null);
  const [error, setError] = useState<string | null>(null);

  const describe = useMutation({
    mutationFn: (meal: string) => callApi((c) => c.tracker.describe({ payload: { text: meal } })),
    onMutate: () => setError(null),
    onSuccess: (estimate) => setRows(estimate.items.map(toRow)),
    onError: (e) => setError(messageOr(e, copy.tracker.describe.failed.text)),
  });

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (text.trim() === "") return setError(copy.validation.required.text);
    describe.mutate(text.trim());
  };

  if (rows === null) {
    return (
      <form onSubmit={submit} noValidate {...stylex.props(styles.form)}>
        <div>
          <h3 {...stylex.props(styles.heading)}>{copy.tracker.describe.heading.text}</h3>
          <p {...stylex.props(styles.hint)}>{copy.tracker.describe.hint.text}</p>
        </div>
        <Textarea
          label={copy.tracker.describe.label.text}
          placeholder={copy.tracker.describe.placeholder.text}
          value={text}
          maxLength={MEAL_DESCRIPTION_MAX}
          rows={3}
          data-autofocus
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            // Enter divines; Shift+Enter starts a new line.
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              e.currentTarget.form?.requestSubmit();
            }
          }}
        />
        {error ? <FormMessage tone="error">{error}</FormMessage> : null}
        <div {...stylex.props(styles.actions)}>
          <Button type="submit" disabled={describe.isPending}>
            {describe.isPending
              ? copy.tracker.describe.divining.text
              : copy.tracker.describe.divine.text}
          </Button>
        </div>
      </form>
    );
  }

  const parsed = rows.map((row) => ({ row, macros: readDraft(row.draft) }));
  const usable = parsed.every((p) => p.row.name.trim() !== "" && p.macros !== null);
  const totals = dayTotals(
    parsed.flatMap((p) => (p.macros ? [{ macros: p.macros, servings: 1 }] : [])),
  );
  const change = (key: string, patch: Partial<Row>) =>
    setRows(rows.map((r) => (r.key === key ? { ...r, ...patch } : r)));

  const log = () => {
    if (!usable || rows.length === 0) return;
    onLog(
      parsed.map(({ row, macros }) => ({
        date,
        slot,
        name: row.name.trim().slice(0, TRACKER_LIMITS.name),
        amount: row.amount.trim() || null,
        servings: 1,
        macros: macros!,
        source: "described" as const,
      })),
    );
  };

  return (
    <div {...stylex.props(styles.form)}>
      <p {...stylex.props(styles.hint)}>{copy.tracker.describe.review.text}</p>
      {rows.length === 0 ? (
        <p {...stylex.props(styles.hint)}>{copy.tracker.describe.nothingLeft.text}</p>
      ) : (
        <ul {...stylex.props(styles.items)}>
          {rows.map((row) => {
            const unknown = row.draft.calories === "" && row.draft.protein === "";
            return (
              <li key={row.key} {...stylex.props(styles.item)}>
                <div {...stylex.props(styles.itemHead)}>
                  <Input
                    label={copy.tracker.entry.name.text}
                    value={row.name}
                    maxLength={TRACKER_LIMITS.name}
                    onChange={(e) => change(row.key, { name: e.target.value })}
                  />
                  <Input
                    label={copy.tracker.entry.amount.text}
                    value={row.amount}
                    maxLength={TRACKER_LIMITS.amount}
                    onChange={(e) => change(row.key, { amount: e.target.value })}
                    xstyle={styles.mono}
                  />
                  <span {...stylex.props(styles.remove)}>
                    <IconButton
                      label={copy.tracker.describe.remove(row.name).text}
                      onClick={() => setRows(rows.filter((r) => r.key !== row.key))}
                    >
                      <CloseGlyph />
                    </IconButton>
                  </span>
                </div>
                {unknown ? (
                  <p {...stylex.props(styles.notFood)}>{copy.tracker.describe.notFood.text}</p>
                ) : null}
                <MacroFields draft={row.draft} onChange={(draft) => change(row.key, { draft })} />
              </li>
            );
          })}
        </ul>
      )}
      <p {...stylex.props(styles.total)}>
        {copy.tracker.describe.total.text}{" "}
        <span {...stylex.props(styles.mono, styles.ink)}>
          {whole(totals.calories)} {copy.tracker.macros.calories.text} · {whole(totals.protein)}
          {copy.tracker.macros.grams.text} {copy.tracker.macros.protein.text} ·{" "}
          {whole(totals.carbs)}
          {copy.tracker.macros.grams.text} {copy.tracker.macros.carbs.text} · {whole(totals.fat)}
          {copy.tracker.macros.grams.text} {copy.tracker.macros.fat.text}
        </span>
        <span {...stylex.props(styles.estimate)}> {copy.tracker.diary.estimate.text}</span>
      </p>
      <div {...stylex.props(styles.actionsSplit)}>
        <Button variant="ghost" onClick={() => setRows(null)}>
          {copy.tracker.describe.startOver.text}
        </Button>
        <Button onClick={log} disabled={!usable || rows.length === 0}>
          {copy.tracker.describe.log(rows.length).text}
        </Button>
      </div>
    </div>
  );
}

const styles = stylex.create({
  form: { display: "flex", flexDirection: "column", gap: 12 },
  heading: { margin: 0, fontSize: 14, fontWeight: 650 },
  hint: { margin: 0, fontSize: 13, color: colors.subtext },
  actions: { display: "flex", justifyContent: "flex-end", gap: 8 },
  actionsSplit: { display: "flex", justifyContent: "space-between", gap: 8 },
  items: {
    listStyle: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
    gap: 10,
  },
  item: {
    display: "flex",
    flexDirection: "column",
    gap: 8,
    padding: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.base,
  },
  itemHead: {
    display: "grid",
    gridTemplateColumns: { default: "2fr 1fr auto", "@media (max-width: 480px)": "1fr auto" },
    alignItems: "end",
    gap: 8,
  },
  remove: { paddingBottom: 2 },
  notFood: { margin: 0, fontSize: 13, color: colors.subtext, fontStyle: "italic" },
  total: { margin: 0, fontSize: 13, color: colors.subtext },
  mono: { fontFamily: fonts.mono, fontVariantNumeric: "tabular-nums" },
  ink: { color: colors.ink },
  estimate: {
    fontFamily: fonts.mono,
    fontSize: 10.5,
    letterSpacing: "0.04em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
});
