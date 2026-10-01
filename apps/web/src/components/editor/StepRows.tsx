import * as stylex from "@stylexjs/stylex";
import { copy, detectTimer, formatTimer, RECIPE_LIMITS } from "@cauldron/shared";
import { type ClipboardEvent, type KeyboardEvent, useEffect, useRef, useState } from "react";
import { splitStepPaste, type StepRow, stepRow } from "../../lib/recipe-form";
import { colors, fonts } from "../../styles/tokens.stylex";
import { CloseGlyph } from "../glyphs";
import { Button, IconButton } from "../ui";
import { control, focusRing } from "../ui/controls";
import { Announcer, DragHandle, useReorder } from "./reorder";

// The method as numbered steps. A time in the text ("bake 25 minutes") becomes
// the step's timer until the cook sets or removes it by hand.

interface Props {
  rows: ReadonlyArray<StepRow>;
  onChange: (rows: Array<StepRow>) => void;
  errors: Readonly<Record<string, string>>;
}

export function StepRows({ rows, onChange, errors }: Props) {
  const inputs = useRef(new Map<string, HTMLTextAreaElement>());
  const [focusKey, setFocusKey] = useState<string | null>(null);
  const [editingTimer, setEditingTimer] = useState<string | null>(null);
  const reorder = useReorder(rows.length, (from, to) => {
    const next = [...rows];
    const [row] = next.splice(from, 1);
    next.splice(to, 0, row!);
    onChange(next);
  });

  useEffect(() => {
    if (!focusKey) return;
    const input = inputs.current.get(focusKey);
    if (input) {
      input.focus();
      input.setSelectionRange(input.value.length, input.value.length);
    }
    setFocusKey(null);
  }, [focusKey]);

  const update = (index: number, row: StepRow) =>
    onChange(rows.map((r, i) => (i === index ? row : r)));

  const insertAfter = (index: number, added: Array<StepRow>) => {
    const next = [...rows];
    next.splice(index + 1, 0, ...added);
    onChange(next);
    const last = added[added.length - 1];
    if (last) setFocusKey(last.key);
  };

  const remove = (index: number) => {
    const next = rows.filter((_, i) => i !== index);
    const fallback = next[Math.max(0, index - 1)];
    onChange(next.length > 0 ? next : [stepRow("")]);
    if (fallback) setFocusKey(fallback.key);
  };

  const setText = (index: number, text: string) => {
    const row = rows[index]!;
    update(index, {
      ...row,
      text,
      timerSeconds: row.timerSet ? row.timerSeconds : detectTimer(text),
      flag: null,
    });
  };

  const onKeyDown = (index: number) => (e: KeyboardEvent<HTMLTextAreaElement>) => {
    const row = rows[index]!;
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      insertAfter(index, [stepRow("")]);
    } else if (e.key === "Backspace" && row.text === "" && rows.length > 1) {
      e.preventDefault();
      remove(index);
    } else if (e.altKey && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
      e.preventDefault();
      reorder.moveTo(index, e.key === "ArrowUp" ? index - 1 : index + 1);
      setFocusKey(row.key);
    }
  };

  const onPaste = (index: number) => (e: ClipboardEvent<HTMLTextAreaElement>) => {
    const pasted = e.clipboardData.getData("text");
    if (!/\r?\n/.test(pasted.trim())) return;
    e.preventDefault();
    const added = splitStepPaste(pasted).map((text) => stepRow(text));
    if (added.length === 0) return;
    if (rows[index]!.text.trim() === "") {
      const next = [...rows];
      next.splice(index, 1, ...added);
      onChange(next);
      setFocusKey(added[added.length - 1]!.key);
    } else {
      insertAfter(index, added);
    }
  };

  return (
    <ol {...stylex.props(styles.list)}>
      {rows.map((row, index) => {
        const error = errors[`steps[${index}]`];
        const label = copy.editor.step(index + 1).text;
        const errorId = error ? `step-error-${row.key}` : undefined;
        return (
          <li
            key={row.key}
            {...reorder.rowProps(index)}
            {...stylex.props(
              styles.row,
              row.flag !== null && styles.flagged,
              reorder.over === index && styles.dropTarget,
            )}
          >
            <div {...stylex.props(styles.side)}>
              <span aria-hidden="true" {...stylex.props(styles.number)}>
                {index + 1}
              </span>
              <DragHandle
                label={`${copy.editor.move.text}: ${label}`}
                {...reorder.handleProps(index)}
              />
            </div>
            <div {...stylex.props(styles.body)}>
              <div {...stylex.props(styles.line)}>
                <textarea
                  ref={(el) => {
                    if (el) inputs.current.set(row.key, el);
                    else inputs.current.delete(row.key);
                  }}
                  aria-label={label}
                  aria-invalid={error ? true : undefined}
                  aria-describedby={errorId}
                  rows={2}
                  value={row.text}
                  onChange={(e) => setText(index, e.target.value)}
                  onKeyDown={onKeyDown(index)}
                  onPaste={onPaste(index)}
                  {...stylex.props(control.field, styles.textarea, error ? control.invalid : null)}
                />
                <IconButton
                  label={`${copy.editor.remove.text}: ${label}`}
                  onClick={() => remove(index)}
                >
                  <CloseGlyph />
                </IconButton>
              </div>
              <Timer
                row={row}
                editing={editingTimer === row.key}
                onEdit={() => setEditingTimer(editingTimer === row.key ? null : row.key)}
                onSet={(timerSeconds) => update(index, { ...row, timerSeconds, timerSet: true })}
              />
              {row.flag ? (
                <p {...stylex.props(styles.note)}>
                  {copy.editor.needsALook.text}: {row.flag}
                </p>
              ) : null}
              {error ? (
                <p id={errorId} {...stylex.props(styles.error)}>
                  {error}
                </p>
              ) : null}
            </div>
          </li>
        );
      })}
      <li {...stylex.props(styles.actions)}>
        <Button variant="secondary" onClick={() => insertAfter(rows.length - 1, [stepRow("")])}>
          {copy.editor.addStep.text}
        </Button>
        <Announcer message={reorder.announcement} />
      </li>
    </ol>
  );
}

function Timer({
  row,
  editing,
  onEdit,
  onSet,
}: {
  row: StepRow;
  editing: boolean;
  onEdit: () => void;
  onSet: (seconds: number | null) => void;
}) {
  const minutes =
    row.timerSeconds === null ? "" : String(Math.round((row.timerSeconds / 60) * 10) / 10);
  return (
    <div {...stylex.props(styles.timerRow)}>
      {row.timerSeconds !== null ? (
        <span {...stylex.props(styles.timer)}>⏲ {formatTimer(row.timerSeconds)}</span>
      ) : null}
      <button
        type="button"
        aria-expanded={editing}
        onClick={onEdit}
        {...stylex.props(styles.timerButton, focusRing.ring)}
      >
        {row.timerSeconds === null ? copy.editor.addTimer.text : copy.editor.changeTimer.text}
      </button>
      {editing ? (
        <>
          <label {...stylex.props(styles.timerLabel)}>
            {copy.editor.timerMinutes.text}
            <input
              type="number"
              min={0}
              step="any"
              max={RECIPE_LIMITS.timerSeconds / 60}
              inputMode="decimal"
              defaultValue={minutes}
              onChange={(e) => {
                const value = Number(e.target.value);
                if (e.target.value === "" || value <= 0) return onSet(null);
                if (Number.isFinite(value)) {
                  onSet(Math.min(Math.round(value * 60), RECIPE_LIMITS.timerSeconds));
                }
              }}
              {...stylex.props(control.field, styles.timerInput)}
            />
          </label>
          {row.timerSeconds !== null ? (
            <Button variant="ghost" onClick={() => onSet(null)}>
              {copy.editor.clearTimer.text}
            </Button>
          ) : null}
        </>
      ) : null}
    </div>
  );
}

const styles = stylex.create({
  list: {
    listStyle: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
    gap: 8,
  },
  row: {
    display: "grid",
    gridTemplateColumns: "auto 1fr",
    gap: 8,
    padding: 4,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "transparent",
  },
  flagged: {
    backgroundColor: `color-mix(in srgb, ${colors.tips} 10%, transparent)`,
    borderColor: `color-mix(in srgb, ${colors.tips} 45%, transparent)`,
  },
  dropTarget: { borderColor: colors.magic },
  side: { display: "flex", flexDirection: "column", alignItems: "center", gap: 2, paddingTop: 6 },
  number: {
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
  body: { display: "flex", flexDirection: "column", gap: 6, minWidth: 0 },
  line: { display: "flex", alignItems: "flex-start", gap: 6 },
  textarea: { flex: 1, minWidth: 0, minHeight: 64, resize: "vertical", lineHeight: 1.5 },
  timerRow: { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 8, minHeight: 28 },
  // Peach is heat: timers. Ink text on a peach wash keeps contrast in Latte.
  timer: {
    display: "inline-flex",
    alignItems: "center",
    gap: 5,
    paddingBlock: 1,
    paddingInline: 8,
    borderRadius: 999,
    fontFamily: fonts.mono,
    fontSize: 12,
    fontWeight: 500,
    color: colors.ink,
    backgroundColor: `color-mix(in srgb, ${colors.heat} 18%, transparent)`,
  },
  timerButton: {
    paddingBlock: 2,
    paddingInline: 8,
    borderWidth: 0,
    borderRadius: 6,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.subtext,
    fontSize: 13,
    textDecorationLine: "underline",
    textDecorationColor: colors.magic,
    textUnderlineOffset: 3,
    cursor: "pointer",
  },
  timerLabel: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    fontSize: 13,
    color: colors.subtext,
  },
  timerInput: {
    width: 96,
    paddingBlock: 4,
    paddingInline: 8,
    fontFamily: fonts.mono,
    fontSize: 14,
  },
  note: { margin: 0, fontSize: 12.5, color: colors.subtext },
  error: { margin: 0, fontSize: 13, fontWeight: 500, color: colors.ink },
  actions: { display: "flex", gap: 8, paddingTop: 6 },
});
