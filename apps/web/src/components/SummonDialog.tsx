import * as stylex from "@stylexjs/stylex";
import { copy, formatTimer } from "@cauldron/shared";
import { useDebouncedValue } from "@tanstack/react-pacer";
import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";
import { type KeyboardEvent, useEffect, useId, useState } from "react";
import { summonQuery } from "../lib/recipes";
import { colors, fonts } from "../styles/tokens.stylex";
import { totalMinutes } from "./RecipeCard";
import { Dialog } from "./ui";
import { control } from "./ui/controls";

// ⌘K: search recipes as you type and jump to them, or to an action. A
// combobox over one listbox, so arrow keys move through recipes and actions.

interface Option {
  readonly id: string;
  readonly label: string;
  readonly detail?: string | undefined;
  readonly go: () => void;
}

export function SummonDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const navigate = useNavigate();
  const id = useId();
  const [text, setText] = useState("");
  const [active, setActive] = useState(0);
  const [q] = useDebouncedValue(text.trim(), { wait: 120 });
  const results = useQuery({ ...summonQuery(q), placeholderData: (previous) => previous });

  useEffect(() => {
    if (!open) setText("");
  }, [open]);

  const close = (go: () => void) => () => {
    onClose();
    go();
  };
  const recipes: Array<Option> =
    q === ""
      ? []
      : (results.data ?? []).map((recipe) => {
          const minutes = totalMinutes(recipe);
          return {
            id: `${id}-r-${recipe.id}`,
            label: recipe.title,
            detail: minutes ? formatTimer(minutes * 60) : undefined,
            go: close(() => void navigate({ to: "/recipes/$id", params: { id: recipe.id } })),
          };
        });
  const actions: Array<Option> = [
    {
      id: `${id}-conjure`,
      label: copy.recipes.conjure.text,
      go: close(() => void navigate({ to: "/recipes/new" })),
    },
    {
      id: `${id}-week`,
      label: copy.library.openWeek.text,
      go: close(() => void navigate({ to: "/week" })),
    },
  ];
  const options = [...recipes, ...actions];
  const current = Math.min(active, options.length - 1);

  useEffect(() => setActive(0), [q]);

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const step = e.key === "ArrowDown" ? 1 : -1;
      setActive((current + step + options.length) % options.length);
    } else if (e.key === "Enter" && !e.nativeEvent.isComposing) {
      e.preventDefault();
      options[current]?.go();
    }
  };

  const item = (option: Option, index: number) => (
    <li
      key={option.id}
      id={option.id}
      role="option"
      aria-selected={index === current}
      onMouseMove={() => setActive(index)}
      onClick={option.go}
      {...stylex.props(styles.option, index === current && styles.optionActive)}
    >
      <span {...stylex.props(styles.label)}>{option.label}</span>
      {option.detail ? <span {...stylex.props(styles.detail)}>{option.detail}</span> : null}
    </li>
  );

  return (
    <Dialog open={open} onClose={onClose} title={copy.recipes.summon.text} hideTitle>
      <input
        type="search"
        role="combobox"
        aria-label={copy.recipes.summon.text}
        aria-expanded="true"
        aria-controls={`${id}-list`}
        aria-activedescendant={options[current]?.id}
        aria-describedby={`${id}-help`}
        placeholder={copy.recipes.summon.text}
        autoComplete="off"
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        data-autofocus
        {...stylex.props(control.field)}
      />
      <p id={`${id}-help`} {...stylex.props(styles.hint)}>
        {q === "" ? copy.recipes.summonHint.text : copy.library.summonHelp.text}
      </p>
      <ul
        id={`${id}-list`}
        role="listbox"
        aria-label={copy.recipes.summon.text}
        {...stylex.props(styles.list)}
      >
        {q !== "" ? (
          <li role="presentation" {...stylex.props(styles.group)}>
            {recipes.length > 0 || results.isFetching
              ? copy.library.results.text
              : copy.library.noResults.text}
          </li>
        ) : null}
        {recipes.map(item)}
        <li role="presentation" {...stylex.props(styles.group)}>
          {copy.library.actions.text}
        </li>
        {actions.map((option, index) => item(option, recipes.length + index))}
      </ul>
    </Dialog>
  );
}

const styles = stylex.create({
  hint: { margin: 0, fontSize: 13, color: colors.subtext },
  list: {
    listStyle: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
    gap: 2,
    maxHeight: "min(60vh, 420px)",
    overflowY: "auto",
  },
  group: {
    paddingTop: 10,
    paddingBottom: 4,
    paddingInline: 10,
    fontFamily: fonts.mono,
    fontSize: 11,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.subtext,
  },
  option: {
    display: "flex",
    alignItems: "baseline",
    justifyContent: "space-between",
    gap: 12,
    paddingBlock: 9,
    paddingInline: 10,
    borderRadius: 8,
    color: colors.ink,
    cursor: "pointer",
  },
  optionActive: { backgroundColor: `color-mix(in srgb, ${colors.magic} 18%, transparent)` },
  label: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" },
  detail: { flexShrink: 0, fontFamily: fonts.mono, fontSize: 12, color: colors.subtext },
});
