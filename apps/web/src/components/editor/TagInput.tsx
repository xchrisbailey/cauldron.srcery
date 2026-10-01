import * as stylex from "@stylexjs/stylex";
import { copy, RECIPE_LIMITS } from "@cauldron/shared";
import { type KeyboardEvent, useId, useState } from "react";
import { colors } from "../../styles/tokens.stylex";
import { CloseGlyph } from "../glyphs";
import { control, focusRing } from "../ui/controls";

// Tags as removable chips. Enter or a comma adds what's typed; Backspace in an
// empty field removes the last tag. Existing tags are offered as suggestions.

export function TagInput({
  tags,
  onChange,
  suggestions,
  error,
  flagged,
}: {
  tags: ReadonlyArray<string>;
  onChange: (tags: Array<string>) => void;
  suggestions: ReadonlyArray<string>;
  error?: string | undefined;
  flagged?: boolean;
}) {
  const id = useId();
  const [draft, setDraft] = useState("");
  const has = (name: string) => tags.some((t) => t.toLowerCase() === name.toLowerCase());

  const add = (raw: string) => {
    const name = raw.trim().slice(0, RECIPE_LIMITS.tag);
    if (name !== "" && !has(name)) onChange([...tags, name]);
    setDraft("");
  };

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.nativeEvent.isComposing) return;
    if (e.key === "Enter" || e.key === ",") {
      e.preventDefault();
      add(draft);
    } else if (e.key === "Backspace" && draft === "" && tags.length > 0) {
      onChange(tags.slice(0, -1));
    }
  };

  return (
    <div {...stylex.props(styles.field)}>
      <label htmlFor={id} {...stylex.props(styles.label)}>
        {copy.editor.tags.text}
      </label>
      <div
        {...stylex.props(
          control.field,
          styles.box,
          flagged && styles.flagged,
          error ? control.invalid : null,
        )}
      >
        {tags.map((tag) => (
          <span key={tag} {...stylex.props(styles.chip)}>
            {tag}
            <button
              type="button"
              aria-label={copy.editor.removeTag(tag).text}
              onClick={() => {
                onChange(tags.filter((t) => t !== tag));
                // The chip's button goes away; keep focus in the field.
                document.getElementById(id)?.focus();
              }}
              {...stylex.props(styles.remove, focusRing.ring)}
            >
              <CloseGlyph />
            </button>
          </span>
        ))}
        <input
          id={id}
          list={`${id}-suggestions`}
          value={draft}
          aria-describedby={`${id}-hint`}
          aria-invalid={error ? true : undefined}
          onChange={(e) => {
            // Picking a suggestion from the list fills the value without a typed
            // character, so typing "pasta bake" never stops at "pasta".
            const value = e.target.value;
            const inputType = (e.nativeEvent as InputEvent).inputType;
            const picked = inputType === undefined || inputType === "insertReplacementText";
            if (picked && suggestions.some((s) => s.toLowerCase() === value.toLowerCase())) {
              add(value);
            } else {
              setDraft(value);
            }
          }}
          onKeyDown={onKeyDown}
          onBlur={() => draft.trim() !== "" && add(draft)}
          {...stylex.props(styles.input)}
        />
        <datalist id={`${id}-suggestions`}>
          {suggestions
            .filter((name) => !has(name))
            .map((name) => (
              <option key={name} value={name} />
            ))}
        </datalist>
      </div>
      <span id={`${id}-hint`} {...stylex.props(styles.hint)}>
        {copy.editor.tagsHint.text}
      </span>
      {error ? <span {...stylex.props(styles.error)}>{error}</span> : null}
    </div>
  );
}

const styles = stylex.create({
  field: { display: "flex", flexDirection: "column", gap: 6 },
  label: { fontSize: 14, fontWeight: 500, color: colors.subtext },
  box: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    gap: 6,
    paddingBlock: 6,
    cursor: "text",
  },
  flagged: { borderColor: colors.tips },
  chip: {
    display: "inline-flex",
    alignItems: "center",
    gap: 2,
    paddingBlock: 2,
    paddingInlineStart: 10,
    paddingInlineEnd: 2,
    borderRadius: 999,
    fontSize: 13,
    fontWeight: 500,
    backgroundColor: colors.surface0,
    color: colors.ink,
  },
  remove: {
    display: "grid",
    placeItems: "center",
    width: 22,
    height: 22,
    padding: 0,
    borderWidth: 0,
    borderRadius: 999,
    backgroundColor: { default: "transparent", ":hover": colors.surface1 },
    color: colors.subtext,
    cursor: "pointer",
  },
  input: {
    flex: 1,
    minWidth: 120,
    borderWidth: 0,
    padding: 4,
    backgroundColor: "transparent",
    color: colors.ink,
    fontSize: 15,
    outline: "none",
  },
  hint: { fontSize: 13, color: colors.subtext },
  error: { fontSize: 13, fontWeight: 500, color: colors.ink },
});
