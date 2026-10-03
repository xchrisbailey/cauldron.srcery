import * as stylex from "@stylexjs/stylex";
import {
  copy,
  type DiaryEntryId,
  type DiaryEntryInput,
  entryTotals,
  type FavouriteId,
  type MealSlot,
  type QuickFood,
} from "@cauldron/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { messageOr } from "../../lib/api-failure";
import { quickFoodsQuery, trackerApi, trackerKeys } from "../../lib/tracker";
import { colors, fonts } from "../../styles/tokens.stylex";
import { StarGlyph } from "../glyphs";
import { Button, IconButton, Skeleton, useToast } from "../ui";
import { focusRing } from "../ui/controls";

// Recents and favourites (#116): what the add sheet opens on. Favourites
// first, then what's been logged lately, most often first. One tap logs it
// again as it was last logged.

const whole = (n: number) => Math.round(n).toLocaleString();

/** Re-logs a food on a day and meal, as it was last logged. */
export const relog = (food: QuickFood, date: string, slot: MealSlot): DiaryEntryInput => ({
  date,
  slot,
  name: food.name,
  amount: food.amount,
  servings: food.servings,
  macros: food.macros,
  source: food.source,
  recipeId: food.recipeId,
});

/** Star and unstar, refreshing the lists. */
export function useStar() {
  const queryClient = useQueryClient();
  const notify = useToast();
  const settle = () => queryClient.invalidateQueries({ queryKey: trackerKeys.quick });
  const fail = (e: unknown) => notify(messageOr(e, copy.tracker.diary.couldntSave.text), "error");
  const star = useMutation({
    mutationFn: (entryId: DiaryEntryId) => trackerApi.favourite(entryId),
    onError: fail,
    onSettled: settle,
  });
  const unstar = useMutation({
    mutationFn: (id: FavouriteId) => trackerApi.unfavourite(id),
    onError: fail,
    onSettled: settle,
  });
  return { star, unstar };
}

export function Recents({
  date,
  slot,
  onLog,
}: {
  date: string;
  slot: MealSlot;
  onLog: (inputs: ReadonlyArray<DiaryEntryInput>) => void;
}) {
  const quick = useQuery(quickFoodsQuery());
  const { star, unstar } = useStar();

  if (quick.isError) {
    return (
      <div {...stylex.props(styles.stack)}>
        <p {...stylex.props(styles.note)}>{copy.tracker.quick.couldntLoad.text}</p>
        <Button variant="secondary" onClick={() => void quick.refetch()}>
          {copy.tracker.diary.retry.text}
        </Button>
      </div>
    );
  }
  if (quick.isPending) {
    return (
      <div aria-busy="true" {...stylex.props(styles.stack)}>
        <Skeleton height={44} />
        <Skeleton height={44} />
        <Skeleton height={44} />
      </div>
    );
  }
  const { favourites, recents } = quick.data;
  if (favourites.length === 0 && recents.length === 0) {
    return <p {...stylex.props(styles.note)}>{copy.tracker.quick.empty.text}</p>;
  }
  return (
    <div {...stylex.props(styles.stack)}>
      {favourites.length > 0 ? (
        <section aria-label={copy.tracker.quick.favourites.text}>
          <h3 {...stylex.props(styles.heading)}>{copy.tracker.quick.favourites.text}</h3>
          <ul {...stylex.props(styles.list)}>
            {favourites.map((f) => (
              <Row
                key={f.id}
                food={f.food}
                starred
                onLog={() => onLog([relog(f.food, date, slot)])}
                onStar={() => unstar.mutate(f.id)}
              />
            ))}
          </ul>
        </section>
      ) : null}
      {recents.length > 0 ? (
        <section aria-label={copy.tracker.quick.recents.text}>
          <h3 {...stylex.props(styles.heading)}>{copy.tracker.quick.recents.text}</h3>
          <ul {...stylex.props(styles.list)}>
            {recents.map((r) => (
              <Row
                key={r.lastEntryId}
                food={r.food}
                count={r.count}
                starred={false}
                onLog={() => onLog([relog(r.food, date, slot)])}
                onStar={() => star.mutate(r.lastEntryId)}
              />
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}

function Row({
  food,
  count,
  starred,
  onLog,
  onStar,
}: {
  food: QuickFood;
  count?: number;
  starred: boolean;
  onLog: () => void;
  onStar: () => void;
}) {
  const totals = entryTotals(food);
  const detail = [food.amount, food.servings === 1 ? null : `× ${+food.servings.toFixed(2)}`]
    .filter(Boolean)
    .join(" ");
  return (
    <li {...stylex.props(styles.row)}>
      <button
        type="button"
        onClick={onLog}
        aria-label={copy.tracker.quick.logAgain(food.name).text}
        {...stylex.props(styles.log, focusRing.ring)}
      >
        <span {...stylex.props(styles.main)}>
          <span {...stylex.props(styles.name)}>{food.name}</span>
          {detail ? <span {...stylex.props(styles.detail)}>{detail}</span> : null}
        </span>
        <span {...stylex.props(styles.numbers)}>
          {whole(totals.calories)} {copy.tracker.macros.calories.text}
          {count !== undefined && count > 1 ? (
            <span {...stylex.props(styles.count)}>{copy.tracker.quick.times(count).text}</span>
          ) : null}
        </span>
      </button>
      <IconButton
        label={
          starred
            ? copy.tracker.quick.unstar(food.name).text
            : copy.tracker.quick.star(food.name).text
        }
        aria-pressed={starred}
        onClick={onStar}
      >
        <span {...stylex.props(styles.star, starred && styles.starOn)}>
          <StarGlyph filled={starred} />
        </span>
      </IconButton>
    </li>
  );
}

const styles = stylex.create({
  stack: { display: "flex", flexDirection: "column", gap: 12 },
  note: { margin: 0, fontSize: 14, color: colors.subtext },
  heading: {
    margin: 0,
    marginBottom: 4,
    fontFamily: fonts.mono,
    fontSize: 10.5,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  list: {
    listStyle: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
    maxHeight: 320,
    overflowY: "auto",
  },
  row: { display: "flex", alignItems: "center", gap: 4 },
  log: {
    flexGrow: 1,
    minWidth: 0,
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    paddingBlock: 9,
    paddingInline: 10,
    borderRadius: 8,
    borderWidth: 0,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
    textAlign: "start",
    cursor: "pointer",
    fontFamily: fonts.ui,
  },
  main: { display: "flex", flexDirection: "column", gap: 2, minWidth: 0 },
  name: {
    fontSize: 15,
    fontWeight: 500,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  detail: { fontFamily: fonts.mono, fontSize: 12, color: colors.subtext },
  numbers: {
    display: "flex",
    alignItems: "baseline",
    gap: 8,
    flexShrink: 0,
    fontFamily: fonts.mono,
    fontSize: 13,
    fontVariantNumeric: "tabular-nums",
  },
  count: { fontSize: 11, color: colors.overlay1 },
  star: { display: "inline-flex" },
  starOn: { color: colors.tips },
});
