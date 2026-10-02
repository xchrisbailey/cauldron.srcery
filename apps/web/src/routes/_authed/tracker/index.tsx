import * as stylex from "@stylexjs/stylex";
import {
  addDays,
  copy,
  dayTotals,
  type DiaryEntry,
  entryTotals,
  hasGaps,
  isRealDate,
  MEAL_SLOTS,
  type MealSlot,
} from "@cauldron/shared";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { PlusGlyph } from "../../../components/glyphs";
import { AddSheet } from "../../../components/tracker/AddSheet";
import { DayHeader } from "../../../components/tracker/DayHeader";
import { EntrySheet } from "../../../components/tracker/EntrySheet";
import {
  Button,
  ButtonLink,
  EmptyState,
  IconButton,
  PageHeader,
  Skeleton,
} from "../../../components/ui";
import { focusRing } from "../../../components/ui/controls";
import { dayLabel } from "../../../lib/dates";
import { useDiaryWrites } from "../../../lib/diary-writes";
import { pageTitle } from "../../../lib/page-title";
import { localToday } from "../../../lib/recipes";
import { dayQuery } from "../../../lib/tracker";
import { colors, fonts } from "../../../styles/tokens.stylex";

// The diary (#113): one day at a time, eaten against target on top, then
// breakfast, lunch, dinner and snack with their entries and subtotals. Every
// change shows at once and rolls back if the API refuses it.

export const Route = createFileRoute("/_authed/tracker/")({
  head: () => pageTitle(copy.nav.tracker),
  validateSearch: (search: Record<string, unknown>): { day?: string } =>
    typeof search.day === "string" && isRealDate(search.day) ? { day: search.day } : {},
  component: Tracker,
});

function Tracker() {
  const search = Route.useSearch();
  // Today is the viewer's own, so it's only known in the browser.
  const [today, setToday] = useState<string | null>(null);
  useEffect(() => setToday(localToday()), []);
  if (today === null) return <DiarySkeleton />;
  return <Diary today={today} date={search.day ?? today} />;
}

function DiarySkeleton() {
  return (
    <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.page)}>
      <Skeleton height={40} width="40%" />
      <Skeleton height={140} />
      <Skeleton height={320} />
    </div>
  );
}

const relative = (date: string, today: string) =>
  date === today
    ? copy.tracker.diary.today.text
    : date === addDays(today, -1)
      ? copy.tracker.diary.yesterday.text
      : date === addDays(today, 1)
        ? copy.tracker.diary.tomorrow.text
        : null;

const searchFor = (date: string, today: string): { day?: string } =>
  date === today ? {} : { day: date };

function Diary({ today, date }: { today: string; date: string }) {
  const queryClient = useQueryClient();
  const day = useQuery(dayQuery(date));
  const writes = useDiaryWrites();
  const [adding, setAdding] = useState<MealSlot | null>(null);
  const [editing, setEditing] = useState<DiaryEntry | null>(null);

  // The days either side, so stepping through doesn't wait.
  useEffect(() => {
    void queryClient.prefetchQuery(dayQuery(addDays(date, -1)));
    void queryClient.prefetchQuery(dayQuery(addDays(date, 1)));
  }, [queryClient, date]);

  const entries = useMemo(() => day.data?.entries ?? [], [day.data]);
  const label = relative(date, today);

  return (
    <div {...stylex.props(styles.page)}>
      <PageHeader
        title={copy.tracker.title.text}
        actions={
          <ButtonLink to="/tracker/targets" variant="secondary">
            {copy.tracker.header.targets.text}
          </ButtonLink>
        }
      />

      <nav aria-label={copy.tracker.diary.pickDay.text} {...stylex.props(styles.dayNav)}>
        <Link
          to="/tracker"
          search={searchFor(addDays(date, -1), today)}
          aria-label={copy.tracker.diary.previousDay.text}
          title={copy.tracker.diary.previousDay.text}
          {...stylex.props(styles.step, focusRing.ring)}
        >
          ‹
        </Link>
        <div {...stylex.props(styles.dayLabel)}>
          <span {...stylex.props(styles.dayName, date === today && styles.today)}>
            {label ?? dayLabel(date, "long")}
          </span>
          <time dateTime={date} {...stylex.props(styles.date)}>
            {date}
          </time>
        </div>
        <Link
          to="/tracker"
          search={searchFor(addDays(date, 1), today)}
          aria-label={copy.tracker.diary.nextDay.text}
          title={copy.tracker.diary.nextDay.text}
          {...stylex.props(styles.step, focusRing.ring)}
        >
          ›
        </Link>
        {date !== today ? (
          <ButtonLink to="/tracker" search={{}} variant="secondary">
            {copy.tracker.diary.today.text}
          </ButtonLink>
        ) : null}
      </nav>

      {day.isError ? (
        <EmptyState
          message={copy.tracker.diary.couldntLoad.text}
          actions={
            <Button variant="secondary" onClick={() => void day.refetch()}>
              {copy.tracker.diary.retry.text}
            </Button>
          }
        />
      ) : day.isPending ? (
        <>
          <Skeleton height={140} />
          <Skeleton height={320} />
        </>
      ) : (
        <>
          <DayHeader totals={day.data.totals} targets={day.data.targets} />
          {entries.length === 0 ? (
            <p {...stylex.props(styles.empty)}>{copy.tracker.diary.empty.text}</p>
          ) : null}
          <div {...stylex.props(styles.slots)}>
            {MEAL_SLOTS.map((slot) => (
              <Slot
                key={slot}
                slot={slot}
                entries={entries.filter((e) => e.slot === slot)}
                onAdd={() => setAdding(slot)}
                onOpen={setEditing}
              />
            ))}
          </div>
        </>
      )}

      <AddSheet
        date={date}
        slot={adding}
        onClose={() => setAdding(null)}
        onLog={(inputs) => {
          setAdding(null);
          void writes.add(inputs);
        }}
      />
      <EntrySheet
        entry={editing}
        today={today}
        onClose={() => setEditing(null)}
        onSave={(entry, change) => {
          setEditing(null);
          if (Object.keys(change).length > 0) void writes.update(entry, change);
        }}
        onRemove={(entry) => {
          setEditing(null);
          void writes.remove(entry);
        }}
      />
    </div>
  );
}

const kcal = (n: number) =>
  `${Math.round(n).toLocaleString()} ${copy.tracker.macros.calories.text}`;

function Slot({
  slot,
  entries,
  onAdd,
  onOpen,
}: {
  slot: MealSlot;
  entries: ReadonlyArray<DiaryEntry>;
  onAdd: () => void;
  onOpen: (entry: DiaryEntry) => void;
}) {
  const subtotal = dayTotals(entries);
  const name = copy.week.slots[slot].text;
  return (
    <section aria-label={name} {...stylex.props(styles.slot)}>
      <div {...stylex.props(styles.slotHead)}>
        <h2 {...stylex.props(styles.slotName)}>{name}</h2>
        {entries.length > 0 ? (
          <span {...stylex.props(styles.subtotal)}>{kcal(subtotal.calories)}</span>
        ) : null}
        <IconButton label={copy.tracker.diary.addTo(name).text} onClick={onAdd}>
          <PlusGlyph />
        </IconButton>
      </div>
      {entries.length > 0 ? (
        <ul {...stylex.props(styles.list)}>
          {entries.map((entry) => (
            <li key={entry.id}>
              <EntryRow entry={entry} onOpen={() => onOpen(entry)} />
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}

function EntryRow({ entry, onOpen }: { entry: DiaryEntry; onOpen: () => void }) {
  const totals = entryTotals(entry);
  const amount = [entry.amount, entry.servings === 1 ? null : `× ${+entry.servings.toFixed(2)}`]
    .filter(Boolean)
    .join(" ");
  return (
    <button
      type="button"
      onClick={onOpen}
      aria-label={copy.tracker.diary.edit(entry.name).text}
      {...stylex.props(styles.entry, focusRing.ring)}
    >
      <span {...stylex.props(styles.entryMain)}>
        <span {...stylex.props(styles.entryName)}>{entry.name}</span>
        <span {...stylex.props(styles.entryMeta)}>
          {amount ? <span {...stylex.props(styles.mono)}>{amount}</span> : null}
          {entry.source === "described" ? (
            <span {...stylex.props(styles.tag)}>{copy.tracker.diary.estimate.text}</span>
          ) : null}
          {hasGaps(entry) ? (
            <span {...stylex.props(styles.tag)}>{copy.tracker.diary.gaps.text}</span>
          ) : null}
        </span>
      </span>
      <span {...stylex.props(styles.entryNumbers)}>
        <span {...stylex.props(styles.entryKcal)}>{kcal(totals.calories)}</span>
        <span {...stylex.props(styles.entryMacros)}>
          <span {...stylex.props(styles.macro)}>
            <span aria-hidden="true" {...stylex.props(styles.dot, styles.protein)} />
            {Math.round(totals.protein)}
            {copy.tracker.macros.grams.text}
          </span>
          <span {...stylex.props(styles.macro)}>
            <span aria-hidden="true" {...stylex.props(styles.dot, styles.carbs)} />
            {Math.round(totals.carbs)}
            {copy.tracker.macros.grams.text}
          </span>
          <span {...stylex.props(styles.macro)}>
            <span aria-hidden="true" {...stylex.props(styles.dot, styles.fat)} />
            {Math.round(totals.fat)}
            {copy.tracker.macros.grams.text}
          </span>
        </span>
      </span>
    </button>
  );
}

const phone = "@media (max-width: 767px)";

const styles = stylex.create({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: { default: 20, [phone]: 16 },
    maxWidth: 760,
    width: "100%",
  },
  dayNav: { display: "flex", alignItems: "center", gap: 8 },
  step: {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    width: 40,
    height: 40,
    borderRadius: 10,
    fontSize: 22,
    lineHeight: 1,
    color: colors.ink,
    textDecoration: "none",
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
  },
  dayLabel: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    minWidth: 150,
    flexGrow: { default: 0, [phone]: 1 },
  },
  dayName: { fontSize: 16, fontWeight: 600, color: colors.ink },
  today: { color: colors.heat },
  date: {
    fontFamily: fonts.mono,
    fontSize: 12,
    color: colors.subtext,
    fontVariantNumeric: "tabular-nums",
  },
  empty: { margin: 0, fontSize: 14, color: colors.subtext },
  slots: { display: "flex", flexDirection: "column", gap: 12 },
  slot: {
    display: "flex",
    flexDirection: "column",
    gap: 4,
    paddingBlock: 8,
    paddingInline: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
  },
  slotHead: { display: "flex", alignItems: "center", gap: 8 },
  slotName: { margin: 0, fontSize: 15, fontWeight: 650, flexGrow: 1 },
  subtotal: {
    fontFamily: fonts.mono,
    fontSize: 13,
    color: colors.subtext,
    fontVariantNumeric: "tabular-nums",
  },
  list: { listStyle: "none", margin: 0, padding: 0, display: "flex", flexDirection: "column" },
  entry: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    width: "100%",
    paddingBlock: 10,
    paddingInline: 8,
    borderRadius: 8,
    borderWidth: 0,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
    textAlign: "start",
    cursor: "pointer",
    fontFamily: fonts.ui,
  },
  entryMain: { display: "flex", flexDirection: "column", gap: 2, minWidth: 0 },
  entryName: {
    fontSize: 15,
    fontWeight: 500,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  entryMeta: { display: "flex", flexWrap: "wrap", gap: 8, fontSize: 12, color: colors.subtext },
  mono: { fontFamily: fonts.mono },
  tag: {
    fontFamily: fonts.mono,
    fontSize: 10.5,
    letterSpacing: "0.04em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  entryNumbers: {
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-end",
    gap: 2,
    flexShrink: 0,
    fontFamily: fonts.mono,
    fontVariantNumeric: "tabular-nums",
  },
  entryKcal: { fontSize: 14, fontWeight: 600 },
  entryMacros: { display: "flex", gap: 8, fontSize: 12, color: colors.subtext },
  macro: { display: "inline-flex", alignItems: "center", gap: 4 },
  dot: { width: 6, height: 6, borderRadius: 999 },
  protein: { backgroundColor: colors.trackerBlue },
  carbs: { backgroundColor: colors.trackerTeal },
  fat: { backgroundColor: colors.trackerRed },
});
