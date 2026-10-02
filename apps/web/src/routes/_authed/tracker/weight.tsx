import * as stylex from "@stylexjs/stylex";
import {
  addDays,
  copy,
  MACRO_KEYS,
  type MacroKey,
  RANGES,
  rangeStart,
  trendChange,
  trendOn,
  trendSeries,
  type WeightRange,
  type WeightUnit,
} from "@cauldron/shared";
import { useQuery } from "@tanstack/react-query";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { Pills } from "../../../components/Choices";
import { WeightChart } from "../../../components/tracker/WeightChart";
import { WeightDialog } from "../../../components/tracker/WeightDialog";
import { Button, EmptyState, PageHeader, Skeleton } from "../../../components/ui";
import { focusRing } from "../../../components/ui/controls";
import { shortDate } from "../../../lib/dates";
import { pageTitle } from "../../../lib/page-title";
import { localToday } from "../../../lib/recipes";
import { showWeight } from "../../../lib/targets";
import { intakeQuery, settingsQuery, weighInsQuery } from "../../../lib/tracker";
import { averageIntake, signedChange } from "../../../lib/weight";
import { useWeighInWrites } from "../../../lib/weigh-in-writes";
import { colors, fonts } from "../../../styles/tokens.stylex";

// Weight (#117): weigh-ins as dots, the smoothed trend as a line, how the trend
// has moved, and what was eaten over the same stretch.

const t = copy.tracker.weight;

export const Route = createFileRoute("/_authed/tracker/weight")({
  head: () => pageTitle(t.pageTitle),
  validateSearch: (search: Record<string, unknown>): { range?: WeightRange } =>
    RANGES.includes(search.range as WeightRange) ? { range: search.range as WeightRange } : {},
  component: WeightPage,
});

function WeightPage() {
  const { range = "3m" } = Route.useSearch();
  // Today is the viewer's own, so it's only known in the browser.
  const [today, setToday] = useState<string | null>(null);
  useEffect(() => setToday(localToday()), []);
  return (
    <div {...stylex.props(styles.page)}>
      <PageHeader title={t.pageTitle.text} />
      {today === null ? <Skeleton height={320} /> : <Weight today={today} range={range} />}
    </div>
  );
}

/**
 * Always fetches the last 365 days of weigh-ins in one go (the API allows up to
 * 367) so the trend is the same whichever range is showing. "All" therefore
 * means the last year, not literally everything; chunking further back can
 * come later.
 */
const FETCH_DAYS = 365;

const MACRO_TINTS = {
  protein: colors.trackerBlue,
  carbs: colors.trackerTeal,
  fat: colors.trackerRed,
} as const;

function Weight({ today, range }: { today: string; range: WeightRange }) {
  const navigate = useNavigate();
  const writes = useWeighInWrites();
  const settings = useQuery(settingsQuery());
  const unit: WeightUnit = settings.data?.profile?.weightUnit ?? "kg";
  const fetchFrom = addDays(today, -FETCH_DAYS);
  const weighIns = useQuery(weighInsQuery(fetchFrom, today));
  const intake = useQuery(intakeQuery(rangeStart(range, today) ?? fetchFrom, today));
  const [editing, setEditing] = useState<{ date: string; weightKg: number } | null>(null);
  const [adding, setAdding] = useState(false);

  const series = useMemo(() => trendSeries(weighIns.data ?? []), [weighIns.data]);
  const start = rangeStart(range, today) ?? series[0]?.date ?? today;
  const visible = useMemo(() => series.filter((p) => p.date >= start), [series, start]);
  const newestFirst = useMemo(() => [...visible].reverse(), [visible]);
  const averages = useMemo(() => averageIntake(intake.data ?? []), [intake.data]);

  if (weighIns.isError) {
    return (
      <EmptyState
        message={t.couldntLoad.text}
        actions={
          <Button variant="secondary" onClick={() => void weighIns.refetch()}>
            {t.retry.text}
          </Button>
        }
      />
    );
  }
  if (weighIns.isPending) return <Skeleton height={320} />;

  const trendNow = trendOn(series, today);
  const week = trendChange(series, 7, today);
  const month = trendChange(series, 30, today);

  return (
    <>
      <div {...stylex.props(styles.toolbar)}>
        <Pills
          small
          mono
          legend={t.rangeLabel.text}
          hideLegend
          value={range}
          onChange={(next) => void navigate({ to: "/tracker/weight", search: { range: next } })}
          options={RANGES.map((value) => ({ value, label: t.ranges[value].text }))}
        />
        <Button variant="secondary" onClick={() => setAdding(true)}>
          {t.add.text}
        </Button>
      </div>

      {series.length === 0 ? (
        <EmptyState
          message={t.empty.text}
          actions={<Button onClick={() => setAdding(true)}>{t.logWeight.text}</Button>}
        />
      ) : (
        <>
          <section aria-label={t.chartLabel.text} {...stylex.props(styles.card)}>
            <WeightChart points={visible} unit={unit} start={start} end={today} />
          </section>

          <section {...stylex.props(styles.stats)}>
            <Stat
              label={t.trendNow.text}
              value={trendNow === null ? null : showWeight(trendNow, unit)}
              unit={unit}
            />
            <Stat
              label={t.lastWeek.text}
              value={week === null ? null : signedChange(week, unit)}
              unit={unit}
            />
            <Stat
              label={t.lastMonth.text}
              value={month === null ? null : signedChange(month, unit)}
              unit={unit}
            />
          </section>

          <section aria-labelledby="intake-title" {...stylex.props(styles.card, styles.cardPad)}>
            <h2 id="intake-title" {...stylex.props(styles.h2)}>
              {t.intakeTitle.text}
            </h2>
            {averages === null ? (
              <p {...stylex.props(styles.note)}>{t.intakeNone.text}</p>
            ) : (
              <>
                <div {...stylex.props(styles.intake)}>
                  {MACRO_KEYS.map((key) => (
                    <Average key={key} keyName={key} value={averages[key]} />
                  ))}
                </div>
                <p {...stylex.props(styles.note)}>{t.intakeAcross(averages.days).text}</p>
              </>
            )}
          </section>

          <section aria-labelledby="list-title" {...stylex.props(styles.card, styles.cardPad)}>
            <h2 id="list-title" {...stylex.props(styles.h2)}>
              {t.listTitle.text}
            </h2>
            <ul {...stylex.props(styles.list)}>
              {newestFirst.map((p) => (
                <li key={p.date} {...stylex.props(styles.row)}>
                  <button
                    type="button"
                    onClick={() => setEditing({ date: p.date, weightKg: p.weightKg })}
                    aria-label={t.edit(shortDate(p.date, true)).text}
                    {...stylex.props(styles.rowMain, focusRing.ring)}
                  >
                    <time dateTime={p.date} {...stylex.props(styles.mono, styles.rowDate)}>
                      {shortDate(p.date, true)}
                    </time>
                    <span {...stylex.props(styles.mono)}>
                      {showWeight(p.weightKg, unit)}
                      <span {...stylex.props(styles.unit)}> {unit}</span>
                    </span>
                  </button>
                  <Button
                    variant="ghost"
                    aria-label={t.removeFor(shortDate(p.date, true)).text}
                    onClick={() => void writes.remove(p.date, p.weightKg)}
                  >
                    {t.remove.text}
                  </Button>
                </li>
              ))}
            </ul>
          </section>
        </>
      )}

      <p {...stylex.props(styles.note)}>
        <Link to="/tracker" {...stylex.props(styles.back, focusRing.ring)}>
          {copy.tracker.title.text}
        </Link>
      </p>

      <WeightDialog
        open={editing !== null}
        onClose={() => setEditing(null)}
        unit={unit}
        title={t.logFor(editing ? shortDate(editing.date, true) : "").text}
        today={today}
        date={editing?.date ?? today}
        weightKg={editing?.weightKg ?? null}
        onSave={(date, kg) => {
          setEditing(null);
          void writes.save(date, kg);
        }}
      />
      <WeightDialog
        open={adding}
        onClose={() => setAdding(false)}
        unit={unit}
        title={t.logTitle.text}
        today={today}
        date={today}
        weightKg={null}
        pickDay
        onSave={(date, kg) => {
          setAdding(false);
          void writes.save(date, kg);
        }}
      />
    </>
  );
}

function Stat({ label, value, unit }: { label: string; value: string | null; unit: WeightUnit }) {
  return (
    <div {...stylex.props(styles.stat)}>
      <span {...stylex.props(styles.statLabel)}>{label}</span>
      {value === null ? (
        <span {...stylex.props(styles.note)}>{t.notEnough.text}</span>
      ) : (
        <span {...stylex.props(styles.statValue)}>
          {value}
          <span {...stylex.props(styles.unit)}> {unit}</span>
        </span>
      )}
    </div>
  );
}

function Average({ keyName, value }: { keyName: MacroKey; value: number }) {
  const unit =
    keyName === "calories" ? copy.tracker.macros.calories.text : copy.tracker.macros.grams.text;
  return (
    <div {...stylex.props(styles.stat)}>
      <span {...stylex.props(styles.statLabel)}>
        {keyName === "calories" ? null : (
          <span
            aria-hidden="true"
            {...stylex.props(
              styles.dot,
              styles.tint(MACRO_TINTS[keyName as keyof typeof MACRO_TINTS]),
            )}
          />
        )}
        {copy.tracker.macroNames[keyName].text}
      </span>
      <span {...stylex.props(styles.statValue)}>
        {Math.round(value).toLocaleString()}
        <span {...stylex.props(styles.unit)}> {unit}</span>
      </span>
    </div>
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
  toolbar: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
  },
  card: {
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
    paddingBlock: 12,
    paddingInline: 12,
  },
  cardPad: {
    display: "flex",
    flexDirection: "column",
    gap: 12,
    paddingBlock: 16,
    paddingInline: 16,
  },
  stats: {
    display: "grid",
    gridTemplateColumns: { default: "repeat(3, 1fr)", [phone]: "1fr" },
    gap: 12,
  },
  stat: {
    display: "flex",
    flexDirection: "column",
    gap: 4,
    paddingBlock: 12,
    paddingInline: 14,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
  },
  statLabel: {
    display: "inline-flex",
    alignItems: "center",
    gap: 6,
    fontFamily: fonts.mono,
    fontSize: 10.5,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.overlay1,
  },
  statValue: {
    fontFamily: fonts.mono,
    fontVariantNumeric: "tabular-nums",
    fontSize: 22,
    fontWeight: 600,
    color: colors.ink,
  },
  unit: { fontSize: 12, fontWeight: 400, color: colors.overlay1 },
  dot: { width: 8, height: 8, borderRadius: 999 },
  tint: (color: string) => ({ backgroundColor: color }),
  h2: { margin: 0, fontSize: 15, fontWeight: 650 },
  note: { margin: 0, fontSize: 13, color: colors.subtext },
  intake: {
    display: "grid",
    gridTemplateColumns: { default: "repeat(4, 1fr)", [phone]: "repeat(2, 1fr)" },
    gap: 12,
  },
  list: { listStyle: "none", margin: 0, padding: 0, display: "flex", flexDirection: "column" },
  row: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: colors.surface0,
  },
  rowMain: {
    display: "flex",
    flexGrow: 1,
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    paddingBlock: 10,
    paddingInline: 8,
    borderWidth: 0,
    borderRadius: 8,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
    cursor: "pointer",
    fontSize: 14,
  },
  rowDate: { color: colors.subtext },
  mono: { fontFamily: fonts.mono, fontVariantNumeric: "tabular-nums" },
  back: { color: colors.subtext },
});
