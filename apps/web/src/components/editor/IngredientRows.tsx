import * as stylex from "@stylexjs/stylex";
import {
  copy,
  formatQuantity,
  parseIngredientLine,
  type ParsedIngredient,
  UNIT_CODES,
  type UnitCode,
  UNITS,
} from "@cauldron/shared";
import { type ClipboardEvent, type KeyboardEvent, useEffect, useRef, useState } from "react";
import {
  type IngredientFormRow,
  type IngredientRow,
  ingredientRow,
  parseQuantity,
  rowKey,
  splitIngredientPaste,
} from "../../lib/recipe-form";
import { colors, fonts, quantity as quantityStyle } from "../../styles/tokens.stylex";
import { CloseGlyph } from "../glyphs";
import { Button, IconButton } from "../ui";
import { control, focusRing } from "../ui/controls";
import { Announcer, DragHandle, useReorder } from "./reorder";

// Ingredient lines as the cook types them, each read live by the shared parser
// into quantity, unit and item chips. "Fix" opens fields to correct a reading;
// retyping the line reads it again. A heading row starts a section.

interface Props {
  rows: ReadonlyArray<IngredientFormRow>;
  onChange: (rows: Array<IngredientFormRow>) => void;
  errors: Readonly<Record<string, string>>;
}

export const unitLabel = (unit: UnitCode) => UNITS[unit].abbr ?? UNITS[unit].singular;

export function IngredientRows({ rows, onChange, errors }: Props) {
  const inputs = useRef(new Map<string, HTMLInputElement>());
  const [focusKey, setFocusKey] = useState<{ key: string; at: "start" | "end" } | null>(null);
  const [fixing, setFixing] = useState<string | null>(null);
  const reorder = useReorder(rows.length, (from, to) => {
    const next = [...rows];
    const [row] = next.splice(from, 1);
    next.splice(to, 0, row!);
    onChange(next);
  });

  useEffect(() => {
    if (!focusKey) return;
    const input = inputs.current.get(focusKey.key);
    if (input) {
      input.focus();
      const at = focusKey.at === "end" ? input.value.length : 0;
      input.setSelectionRange(at, at);
    }
    setFocusKey(null);
  }, [focusKey]);

  const update = (index: number, row: IngredientFormRow) =>
    onChange(rows.map((r, i) => (i === index ? row : r)));

  const insertAfter = (index: number, added: Array<IngredientFormRow>) => {
    const next = [...rows];
    next.splice(index + 1, 0, ...added);
    onChange(next);
    const last = added[added.length - 1];
    if (last) setFocusKey({ key: last.key, at: "end" });
  };

  const remove = (index: number) => {
    const next = rows.filter((_, i) => i !== index);
    const fallback = next[Math.max(0, index - 1)];
    onChange(next.length > 0 ? next : [ingredientRow("")]);
    if (fallback) setFocusKey({ key: fallback.key, at: "end" });
  };

  const setText = (index: number, text: string) => {
    const row = rows[index]!;
    if (row.kind === "heading") return update(index, { ...row, text, flag: null });
    update(index, {
      ...row,
      text,
      parsed: parseIngredientLine(text),
      corrected: false,
      flag: null,
    });
  };

  const onKeyDown = (index: number) => (e: KeyboardEvent<HTMLInputElement>) => {
    const row = rows[index]!;
    if (e.nativeEvent.isComposing) return;
    if (e.key === "Enter") {
      e.preventDefault();
      insertAfter(index, [ingredientRow("")]);
    } else if (e.key === "Backspace" && row.text === "" && rows.length > 1) {
      e.preventDefault();
      remove(index);
    } else if (e.altKey && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
      e.preventDefault();
      reorder.moveTo(index, e.key === "ArrowUp" ? index - 1 : index + 1);
      setFocusKey({ key: row.key, at: "end" });
    }
  };

  const onPaste = (index: number) => (e: ClipboardEvent<HTMLInputElement>) => {
    const pasted = e.clipboardData.getData("text");
    if (!/\r?\n/.test(pasted.trim())) return;
    e.preventDefault();
    const added = splitIngredientPaste(pasted).map((line) => ingredientRow(line));
    if (added.length === 0) return;
    // An empty row takes the first pasted line; otherwise they go below it.
    if (rows[index]!.text.trim() === "") {
      const next = [...rows];
      next.splice(index, 1, ...added);
      onChange(next);
      setFocusKey({ key: added[added.length - 1]!.key, at: "end" });
    } else {
      insertAfter(index, added);
    }
  };

  let lineNumber = 0;
  let headingNumber = 0;
  return (
    <div {...stylex.props(styles.list)}>
      {rows.map((row, index) => {
        const error = errors[`ingredients[${index}]`];
        const label =
          row.kind === "heading"
            ? copy.editor.heading(++headingNumber).text
            : copy.editor.ingredientLine(++lineNumber).text;
        const errorId = error ? `ingredient-error-${row.key}` : undefined;
        const flagId = row.flag ? `ingredient-flag-${row.key}` : undefined;
        return (
          <div
            key={row.key}
            {...reorder.rowProps(index)}
            {...stylex.props(
              styles.row,
              row.flag !== null && styles.flagged,
              reorder.over === index && styles.dropTarget,
            )}
          >
            <div {...stylex.props(styles.line)}>
              <DragHandle
                label={`${copy.editor.move.text}: ${label}`}
                {...reorder.handleProps(index)}
              />
              <input
                ref={(el) => {
                  if (el) inputs.current.set(row.key, el);
                  else inputs.current.delete(row.key);
                }}
                aria-label={label}
                aria-invalid={error ? true : undefined}
                aria-describedby={[errorId, flagId].filter(Boolean).join(" ") || undefined}
                value={row.text}
                onChange={(e) => setText(index, e.target.value)}
                onKeyDown={onKeyDown(index)}
                onPaste={onPaste(index)}
                autoComplete="off"
                spellCheck
                {...stylex.props(
                  control.field,
                  styles.input,
                  row.kind === "heading" && styles.headingInput,
                  error ? control.invalid : null,
                )}
              />
              <IconButton
                label={`${copy.editor.remove.text}: ${label}`}
                onClick={() => remove(index)}
              >
                <CloseGlyph />
              </IconButton>
            </div>
            {row.kind === "line" && row.text.trim() !== "" ? (
              <Reading
                row={row}
                open={fixing === row.key}
                onToggle={() => setFixing(fixing === row.key ? null : row.key)}
                onCorrect={(parsed) =>
                  update(index, { ...row, parsed, corrected: true, flag: null })
                }
                onReset={() =>
                  update(index, { ...row, parsed: parseIngredientLine(row.text), corrected: false })
                }
              />
            ) : null}
            {row.flag ? (
              <p id={flagId} {...stylex.props(styles.flagNote)}>
                {copy.editor.needsALook.text}: {row.flag}
              </p>
            ) : null}
            {error ? (
              <p id={errorId} {...stylex.props(styles.error)}>
                {error}
              </p>
            ) : null}
          </div>
        );
      })}
      <div {...stylex.props(styles.actions)}>
        <Button
          variant="secondary"
          onClick={() => insertAfter(rows.length - 1, [ingredientRow("")])}
        >
          {copy.editor.addIngredient.text}
        </Button>
        <Button
          variant="ghost"
          onClick={() =>
            insertAfter(rows.length - 1, [{ key: rowKey(), kind: "heading", text: "", flag: null }])
          }
        >
          {copy.editor.addHeading.text}
        </Button>
      </div>
      <Announcer message={reorder.announcement} />
    </div>
  );
}

/** The parser's reading of one line as chips, and the fields to correct it. */
function Reading({
  row,
  open,
  onToggle,
  onCorrect,
  onReset,
}: {
  row: IngredientRow;
  open: boolean;
  onToggle: () => void;
  onCorrect: (parsed: ParsedIngredient) => void;
  onReset: () => void;
}) {
  const { parsed } = row;
  const [quantityText, setQuantityText] = useState(
    parsed.quantity ? formatQuantity(parsed.quantity, null).replace("–", "-") : "",
  );
  const [quantityError, setQuantityError] = useState(false);
  useEffect(() => {
    if (!open) {
      setQuantityText(
        parsed.quantity ? formatQuantity(parsed.quantity, null).replace("–", "-") : "",
      );
      setQuantityError(false);
    }
  }, [open, parsed.quantity]);

  return (
    <div {...stylex.props(styles.reading)}>
      <div {...stylex.props(styles.chips)}>
        <span {...stylex.props(styles.chip, styles.quantityChip)}>
          {parsed.quantity ? (
            <span {...stylex.props(quantityStyle.value)}>
              {formatQuantity(parsed.quantity, parsed.unit)}
            </span>
          ) : (
            <span {...stylex.props(styles.empty)}>—</span>
          )}
          {parsed.unit ? (
            <span {...stylex.props(quantityStyle.value, quantityStyle.unit)}>
              {unitLabel(parsed.unit)}
            </span>
          ) : null}
        </span>
        {parsed.alt ? (
          <span {...stylex.props(styles.note, quantityStyle.value)}>
            ({formatQuantity(parsed.alt.quantity, parsed.alt.unit)} {unitLabel(parsed.alt.unit)})
          </span>
        ) : null}
        <span {...stylex.props(styles.chip)}>{parsed.item || "—"}</span>
        {parsed.note ? <span {...stylex.props(styles.note)}>{parsed.note}</span> : null}
        {parsed.optional ? (
          <span {...stylex.props(styles.pill)}>{copy.editor.optional.text}</span>
        ) : null}
        <button
          type="button"
          aria-expanded={open}
          aria-label={copy.editor.fixLine(row.text).text}
          onClick={onToggle}
          {...stylex.props(styles.fix, focusRing.ring)}
        >
          {copy.editor.fix.text}
        </button>
      </div>
      {open ? (
        <div {...stylex.props(styles.fixFields)}>
          <label {...stylex.props(styles.fixLabel)}>
            {copy.editor.quantity.text}
            <input
              value={quantityText}
              inputMode="decimal"
              aria-invalid={quantityError ? true : undefined}
              onChange={(e) => {
                setQuantityText(e.target.value);
                const next = parseQuantity(e.target.value);
                setQuantityError(next === "invalid");
                if (next !== "invalid") onCorrect({ ...parsed, quantity: next });
              }}
              {...stylex.props(
                control.field,
                styles.small,
                styles.mono,
                quantityError && control.invalid,
              )}
            />
            {quantityError ? (
              <span {...stylex.props(styles.error)}>{copy.editor.badQuantity.text}</span>
            ) : null}
          </label>
          <label {...stylex.props(styles.fixLabel)}>
            {copy.editor.unit.text}
            <select
              value={parsed.unit ?? ""}
              onChange={(e) =>
                onCorrect({
                  ...parsed,
                  unit: e.target.value === "" ? null : (e.target.value as UnitCode),
                })
              }
              {...stylex.props(control.field, control.select, styles.small, styles.mono)}
            >
              <option value="">{copy.editor.noUnit.text}</option>
              {UNIT_CODES.map((code) => (
                <option key={code} value={code}>
                  {unitLabel(code)}
                </option>
              ))}
            </select>
          </label>
          <label {...stylex.props(styles.fixLabel, styles.grow)}>
            {copy.editor.item.text}
            <input
              value={parsed.item}
              onChange={(e) => onCorrect({ ...parsed, item: e.target.value })}
              {...stylex.props(control.field, styles.small)}
            />
          </label>
          <label {...stylex.props(styles.fixLabel, styles.grow)}>
            {copy.editor.note.text}
            <input
              value={parsed.note ?? ""}
              onChange={(e) =>
                onCorrect({ ...parsed, note: e.target.value === "" ? null : e.target.value })
              }
              {...stylex.props(control.field, styles.small)}
            />
          </label>
          <label {...stylex.props(styles.check)}>
            <input
              type="checkbox"
              checked={parsed.optional}
              onChange={(e) => onCorrect({ ...parsed, optional: e.target.checked })}
            />
            {copy.editor.optional.text}
          </label>
          {row.corrected ? (
            <Button variant="ghost" onClick={onReset}>
              {copy.editor.resetLine.text}
            </Button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

const styles = stylex.create({
  list: { display: "flex", flexDirection: "column", gap: 6 },
  row: {
    display: "flex",
    flexDirection: "column",
    gap: 4,
    paddingBlock: 4,
    paddingInline: 4,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "transparent",
  },
  // An import wants this one checked: the Tips color, as in the brand book.
  flagged: {
    backgroundColor: `color-mix(in srgb, ${colors.tips} 10%, transparent)`,
    borderColor: `color-mix(in srgb, ${colors.tips} 45%, transparent)`,
  },
  dropTarget: { borderColor: colors.magic },
  line: { display: "flex", alignItems: "center", gap: 6 },
  input: { flex: 1, minWidth: 0, paddingBlock: 8 },
  headingInput: { fontWeight: 650, fontSize: 16 },
  reading: { display: "flex", flexDirection: "column", gap: 8, paddingInlineStart: 34 },
  chips: { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 6, fontSize: 13 },
  chip: {
    display: "inline-flex",
    alignItems: "baseline",
    paddingBlock: 2,
    paddingInline: 8,
    borderRadius: 999,
    backgroundColor: colors.surface0,
    color: colors.ink,
  },
  quantityChip: { minWidth: 32, justifyContent: "flex-end", gap: 4 },
  empty: { color: colors.overlay1, fontFamily: fonts.mono },
  note: { color: colors.subtext },
  pill: {
    fontFamily: fonts.mono,
    fontSize: 10.5,
    fontWeight: 600,
    letterSpacing: "0.05em",
    textTransform: "uppercase",
    paddingBlock: 3,
    paddingInline: 7,
    borderRadius: 999,
    backgroundColor: colors.surface0,
    color: colors.subtext,
  },
  fix: {
    marginInlineStart: "auto",
    paddingBlock: 2,
    paddingInline: 8,
    borderWidth: 0,
    borderRadius: 6,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.subtext,
    fontFamily: fonts.ui,
    fontSize: 13,
    textDecorationLine: "underline",
    textDecorationColor: colors.magic,
    textUnderlineOffset: 3,
    cursor: "pointer",
  },
  fixFields: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "flex-end",
    gap: 10,
    padding: 10,
    borderRadius: 10,
    backgroundColor: colors.mantle,
  },
  fixLabel: {
    display: "flex",
    flexDirection: "column",
    gap: 4,
    fontSize: 12,
    color: colors.subtext,
    width: 110,
  },
  grow: { flex: 1, minWidth: 140 },
  small: { paddingBlock: 6, paddingInline: 8, fontSize: 14 },
  mono: { fontFamily: fonts.mono },
  check: { display: "flex", alignItems: "center", gap: 6, fontSize: 13, minHeight: 34 },
  flagNote: { margin: 0, paddingInlineStart: 34, fontSize: 12.5, color: colors.subtext },
  error: { margin: 0, paddingInlineStart: 34, fontSize: 13, fontWeight: 500, color: colors.ink },
  actions: { display: "flex", flexWrap: "wrap", gap: 8, paddingTop: 6 },
});
