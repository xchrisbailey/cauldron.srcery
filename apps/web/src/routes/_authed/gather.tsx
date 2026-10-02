import * as stylex from "@stylexjs/stylex";
import {
  AISLES,
  copy,
  type GatherItem,
  type GatherItemUpdate,
  type GatherList,
  measureParts,
  RECIPE_LIMITS,
} from "@cauldron/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { type FormEvent, useState } from "react";
import { CloseGlyph } from "../../components/glyphs";
import { WeekRange } from "../../components/WeekRange";
import {
  Button,
  ButtonLink,
  EmptyState,
  IconButton,
  PageHeader,
  Skeleton,
  useToast,
} from "../../components/ui";
import { control } from "../../components/ui/controls";
import {
  addGatherItem,
  applyItemUpdate,
  gatherKeys,
  gatherQuery,
  removeGatherItem,
  updateGatherItem,
} from "../../lib/gather";
import { retryWhile } from "../../lib/api-failure";
import { usePreference } from "../../lib/preference";
import { useWeekCursor, type WeekCursor, weekSearch } from "../../lib/week-cursor";
import { colors, fonts, quantity } from "../../styles/tokens.stylex";
import { pageTitle } from "../../lib/page-title";

// The Gather list (#19): the week's shopping, merged and grouped by aisle.
// Checking items off changes the list at once and keeps retrying in the
// background, so a patchy signal in the shop doesn't lose a tick.

export const Route = createFileRoute("/_authed/gather")({
  head: () => pageTitle(copy.nav.gather),
  validateSearch: weekSearch,
  component: Gather,
});

const HIDE_KEY = "cauldron:gather-hide-checked";

function Gather() {
  const search = Route.useSearch();
  const cursor = useWeekCursor(search.week);
  const [hideChecked, setHideChecked, hideLoaded] = usePreference(
    HIDE_KEY,
    (raw) => raw === "1",
    false,
    (hide) => (hide ? "1" : "0"),
  );
  if (cursor === null || !hideLoaded) return <Skeleton height={320} />;
  return <List cursor={cursor} hideChecked={hideChecked} toggleHide={setHideChecked} />;
}

type Week = GatherList;

function List({
  cursor: { start, thisWeek, searchFor },
  hideChecked,
  toggleHide,
}: {
  cursor: WeekCursor;
  hideChecked: boolean;
  toggleHide: (hide: boolean) => void;
}) {
  const queryClient = useQueryClient();
  const toast = useToast();
  const list = useQuery(gatherQuery(start));
  const [line, setLine] = useState("");
  const key = gatherKeys.week(start);

  const prefetchWeek = (weekStart: string) =>
    void queryClient.prefetchQuery(gatherQuery(weekStart));

  // Each change sets a value rather than toggling, and changes run one at a
  // time in the order they were made, so retries can't land out of order.
  const update = useMutation({
    mutationKey: ["gather", "update"],
    scope: { id: "gather-update" },
    mutationFn: ({ item, update }: { item: GatherItem; update: GatherItemUpdate }) =>
      updateGatherItem(item.id, update),
    retry: retryWhile(5),
    onMutate: async ({ item, update }) => {
      await queryClient.cancelQueries({ queryKey: key });
      queryClient.setQueryData<Week>(key, (week) =>
        week ? applyItemUpdate(week, item.id, update) : week,
      );
    },
    // Undo just this change, leaving any others still in flight.
    onError: (_error, { item, update }) => {
      queryClient.setQueryData<Week>(key, (week) =>
        week
          ? applyItemUpdate(week, item.id, {
              ...(update.checked === undefined ? {} : { checked: item.checked }),
              ...(update.inPantry === undefined ? {} : { inPantry: item.inPantry }),
            })
          : week,
      );
      toast(copy.gather.couldntSave.text, "error");
    },
    onSettled: () => {
      if (queryClient.isMutating({ mutationKey: ["gather", "update"] }) <= 1) {
        void queryClient.invalidateQueries({ queryKey: key });
      }
    },
  });

  const add = useMutation({
    mutationFn: (text: string) => addGatherItem(start, text),
    onSuccess: (item) => {
      setLine("");
      queryClient.setQueryData<Week>(key, (week) =>
        week ? { ...week, items: [...week.items, item] } : week,
      );
    },
    onError: () => toast(copy.gather.couldntSave.text, "error"),
    onSettled: () => void queryClient.invalidateQueries({ queryKey: key }),
  });

  const remove = useMutation({
    mutationFn: (item: GatherItem) => removeGatherItem(item.id),
    onMutate: async (item) => {
      await queryClient.cancelQueries({ queryKey: key });
      const saved = queryClient.getQueryData<Week>(key);
      queryClient.setQueryData<Week>(key, (week) =>
        week ? { ...week, items: week.items.filter((i) => i.id !== item.id) } : week,
      );
      return saved;
    },
    onError: (_error, _vars, saved) => {
      queryClient.setQueryData(key, saved);
      toast(copy.gather.couldntSave.text, "error");
    },
    onSettled: () => void queryClient.invalidateQueries({ queryKey: key }),
  });

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (line.trim() !== "") add.mutate(line.trim());
  };

  const items = list.data?.items ?? [];
  const done = items.filter((i) => i.checked).length;
  const shown = hideChecked ? items.filter((i) => !i.checked) : items;

  return (
    <div {...stylex.props(styles.page)}>
      <PageHeader
        title={copy.gather.title.text}
        actions={
          items.length > 0 ? (
            <label {...stylex.props(styles.hide)}>
              <input
                type="checkbox"
                checked={hideChecked}
                onChange={(e) => toggleHide(e.target.checked)}
                {...stylex.props(styles.check)}
              />
              {copy.gather.hideChecked.text}
            </label>
          ) : null
        }
      />
      <WeekRange start={start} thisWeek={thisWeek} searchFor={searchFor} prefetch={prefetchWeek} />

      <form onSubmit={submit} {...stylex.props(styles.addRow)}>
        <input
          aria-label={copy.gather.addItem.text}
          placeholder={copy.gather.addPlaceholder.text}
          maxLength={RECIPE_LIMITS.line}
          value={line}
          onChange={(e) => setLine(e.target.value)}
          {...stylex.props(control.field)}
        />
        <Button type="submit" variant="secondary" disabled={line.trim() === "" || add.isPending}>
          {copy.gather.add.text}
        </Button>
      </form>

      {list.isError ? (
        <EmptyState
          message={copy.gather.couldntLoad.text}
          actions={
            <Button variant="secondary" onClick={() => void list.refetch()}>
              {copy.gather.retry.text}
            </Button>
          }
        />
      ) : list.isPending ? (
        <Skeleton height={320} />
      ) : items.length === 0 ? (
        <EmptyState
          message={copy.gather.empty.text}
          actions={
            <ButtonLink to="/week" search={searchFor(start)} variant="secondary">
              {copy.nav.week.text}
            </ButtonLink>
          }
        />
      ) : (
        <>
          <p aria-live="polite" {...stylex.props(styles.progress)}>
            {done === items.length
              ? copy.gather.allChecked.text
              : copy.gather.checked(done, items.length).text}
          </p>
          {AISLES.map((aisle) => {
            const here = shown.filter((i) => i.aisle === aisle);
            if (here.length === 0) return null;
            return (
              <section key={aisle} aria-labelledby={`aisle-${aisle}`}>
                <h2 id={`aisle-${aisle}`} {...stylex.props(styles.aisle)}>
                  {copy.gather.aisles[aisle].text}
                </h2>
                <ul {...stylex.props(styles.items)}>
                  {here.map((item) => (
                    <Item
                      key={item.id}
                      item={item}
                      onCheck={(checked) => update.mutate({ item, update: { checked } })}
                      onPantry={(inPantry) => update.mutate({ item, update: { inPantry } })}
                      onRemove={() => remove.mutate(item)}
                    />
                  ))}
                </ul>
              </section>
            );
          })}
        </>
      )}
    </div>
  );
}

function Item({
  item,
  onCheck,
  onPantry,
  onRemove,
}: {
  item: GatherItem;
  onCheck: (checked: boolean) => void;
  onPantry: (inPantry: boolean) => void;
  onRemove: () => void;
}) {
  const measure = item.quantity ? measureParts(item.quantity, item.unit) : null;
  const sources = item.sources.map((s) => s.title).join(", ");
  return (
    <li {...stylex.props(styles.item, item.inPantry && styles.itemPantry)}>
      <label {...stylex.props(styles.line)}>
        <input
          type="checkbox"
          checked={item.checked}
          onChange={(e) => onCheck(e.target.checked)}
          {...stylex.props(styles.check)}
        />
        <span {...stylex.props(styles.amount, quantity.value)}>
          {measure ? (
            <>
              {measure.amount}
              {measure.unit ? <span {...stylex.props(quantity.unit)}> {measure.unit}</span> : null}
            </>
          ) : null}
        </span>
        <span {...stylex.props(styles.text)}>
          <span {...stylex.props(item.checked && styles.struck)}>{item.item}</span>
          <span {...stylex.props(styles.sources)}>
            {item.manual ? copy.gather.addedByHand.text : copy.gather.forRecipes(sources).text}
          </span>
        </span>
      </label>
      <label {...stylex.props(styles.pantry, item.inPantry && styles.pantryOn)}>
        <input
          type="checkbox"
          checked={item.inPantry}
          onChange={(e) => onPantry(e.target.checked)}
          aria-label={copy.gather.markInPantry(item.item).text}
          {...stylex.props(styles.srOnly)}
        />
        {item.inPantry ? <span aria-hidden="true">✓ </span> : null}
        {copy.gather.inPantry.text}
      </label>
      {item.manual ? (
        <IconButton label={copy.gather.remove(item.item).text} onClick={onRemove}>
          <CloseGlyph />
        </IconButton>
      ) : null}
    </li>
  );
}

const phone = "@media (max-width: 767px)";

const styles = stylex.create({
  page: { display: "flex", flexDirection: "column", gap: 16, maxWidth: 760 },
  hide: { display: "flex", alignItems: "center", gap: 8, fontSize: 14, color: colors.subtext },
  addRow: { display: "flex", gap: 8 },
  progress: { margin: 0, fontFamily: fonts.mono, fontSize: 12.5, color: colors.subtext },
  aisle: {
    margin: 0,
    marginTop: 8,
    marginBottom: 4,
    fontFamily: fonts.mono,
    fontSize: 11,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.subtext,
  },
  items: { listStyle: "none", margin: 0, padding: 0 },
  item: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: colors.surface0,
  },
  // The Fresh color, as a wash behind ink text so it keeps contrast in Latte.
  itemPantry: { backgroundColor: `color-mix(in srgb, ${colors.fresh} 12%, transparent)` },
  line: {
    flexGrow: 1,
    minWidth: 0,
    display: "grid",
    gridTemplateColumns: "18px minmax(64px, max-content) minmax(0, 1fr)",
    alignItems: "baseline",
    gap: 10,
    paddingBlock: { default: 8, [phone]: 12 },
    paddingInlineStart: 4,
    fontSize: 15,
    cursor: "pointer",
  },
  check: { margin: 0, width: 18, height: 18, accentColor: colors.magic, alignSelf: "center" },
  amount: { textAlign: "end" },
  text: { display: "flex", flexDirection: "column", gap: 2, minWidth: 0 },
  struck: {
    color: colors.overlay1,
    textDecorationLine: "line-through",
    textDecorationColor: colors.overlay0,
  },
  sources: {
    fontSize: 12.5,
    color: colors.subtext,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  pantry: {
    flexShrink: 0,
    paddingBlock: 4,
    paddingInline: 10,
    minHeight: { default: 28, [phone]: 36 },
    display: "inline-flex",
    alignItems: "center",
    borderRadius: 999,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface1,
    fontSize: 12,
    color: colors.subtext,
    cursor: "pointer",
    outline: { default: "none", ":has(:focus-visible)": `2px solid ${colors.magic}` },
    outlineOffset: 2,
  },
  pantryOn: {
    fontWeight: 600,
    borderColor: colors.fresh,
    backgroundColor: `color-mix(in srgb, ${colors.fresh} 22%, transparent)`,
    color: colors.ink,
  },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
});
