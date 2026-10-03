import * as stylex from "@stylexjs/stylex";
import { addDays, copy, type MacroKey, type WeightUnit } from "@cauldron/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import {
  Button,
  ButtonLink,
  EmptyState,
  FormMessage,
  PageHeader,
  Skeleton,
  useToast,
} from "../../../components/ui";
import { messageOr } from "../../../lib/api-failure";
import { buildCheckIn, checkInFrom } from "../../../lib/check-in";
import { pageTitle } from "../../../lib/page-title";
import { localToday } from "../../../lib/recipes";
import {
  intakeQuery,
  settingsQuery,
  trackerApi,
  trackerKeys,
  weighInsQuery,
} from "../../../lib/tracker";
import { signedChange } from "../../../lib/weight";
import { colors, fonts } from "../../../styles/tokens.stylex";

// The weekly check-in (#118): what was eaten and how the weight trend moved say
// what the body is burning; the targets are re-proposed from that. Nothing
// changes until it's accepted.

const t = copy.tracker.checkIn;

export const Route = createFileRoute("/_authed/tracker/check-in")({
  head: () => pageTitle(t.pageTitle),
  component: CheckInPage,
});

function CheckInPage() {
  // Today is the viewer's own, so it's only known in the browser.
  const [today, setToday] = useState<string | null>(null);
  useEffect(() => setToday(localToday()), []);
  return (
    <div {...stylex.props(styles.page)}>
      <PageHeader title={t.title.text} />
      {today === null ? <Skeleton height={320} /> : <CheckIn today={today} />}
    </div>
  );
}

const MACROS: ReadonlyArray<{ key: MacroKey; tint: string | null; unit: string }> = [
  { key: "calories", tint: null, unit: copy.tracker.macros.calories.text },
  { key: "protein", tint: colors.trackerBlue, unit: copy.tracker.macros.grams.text },
  { key: "carbs", tint: colors.trackerTeal, unit: copy.tracker.macros.grams.text },
  { key: "fat", tint: colors.trackerRed, unit: copy.tracker.macros.grams.text },
];

const NOT_HAND_SET = { calories: false, protein: false, carbs: false, fat: false };

/** A signed weekly change in the cook's unit, e.g. "−0.5 kg a week". */
const perWeek = (kg: number, unit: WeightUnit) => t.perWeek(signedChange(kg, unit), unit).text;

function CheckIn({ today }: { today: string }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const toast = useToast();
  const settings = useQuery(settingsQuery());
  const weighIns = useQuery(weighInsQuery(addDays(today, -365), today));
  const intake = useQuery(intakeQuery(checkInFrom(today), today));
  const [keepOverrides, setKeepOverrides] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const checkIn = useMemo(
    () =>
      settings.data && weighIns.data && intake.data
        ? buildCheckIn({
            settings: settings.data,
            intake: intake.data,
            weighIns: weighIns.data,
            today,
            keepOverrides,
          })
        : null,
    [settings.data, weighIns.data, intake.data, today, keepOverrides],
  );

  const save = useMutation({
    mutationFn: (accept: boolean) => {
      const current = settings.data!.targets!;
      const next = accept && checkIn ? checkIn.proposal.targets : current;
      return trackerApi.saveTargets({
        calories: next.calories,
        protein: next.protein,
        carbs: next.carbs,
        fat: next.fat,
        overridden: accept && !keepOverrides ? NOT_HAND_SET : current.overridden,
        checkedInOn: today,
      });
    },
    onSuccess: (_, accept) => {
      toast(accept ? t.accepted.text : t.deferred.text);
      void navigate({ to: "/tracker" });
    },
    onError: (e) => setError(messageOr(e, t.couldntSave.text)),
    onSettled: () => queryClient.invalidateQueries({ queryKey: trackerKeys.all }),
  });

  if (settings.isError || weighIns.isError || intake.isError) {
    return (
      <EmptyState
        message={t.couldntLoad.text}
        actions={
          <Button
            variant="secondary"
            onClick={() => {
              void settings.refetch();
              void weighIns.refetch();
              void intake.refetch();
            }}
          >
            {t.retry.text}
          </Button>
        }
      />
    );
  }
  if (settings.isPending || weighIns.isPending || intake.isPending)
    return <Skeleton height={320} />;

  const { profile, targets } = settings.data;
  if (!profile || !targets || !checkIn) {
    return (
      <EmptyState
        message={t.needTargets.text}
        actions={
          <ButtonLink to="/tracker/targets" variant="primary">
            {copy.tracker.header.setTargets.text}
          </ButtonLink>
        }
      />
    );
  }

  const unit = profile.weightUnit;
  const { estimate, proposal } = checkIn;
  const anyHandSet = Object.values(targets.overridden).some(Boolean);
  const unchanged = MACROS.every(({ key }) => proposal.targets[key] === targets[key]);
  const thin =
    estimate.measured === null ? t.thin.text : estimate.confidence < 0.5 ? t.leans.text : null;

  return (
    <>
      <section aria-label={t.expenditure.text} {...stylex.props(styles.block)}>
        <h2 {...stylex.props(styles.label)}>{t.expenditure.text}</h2>
        <p {...stylex.props(styles.big)}>
          {estimate.expenditure.toLocaleString()}
          <span {...stylex.props(styles.bigUnit)}> {t.perDay.text}</span>
        </p>
        <p {...stylex.props(styles.note)}>
          {t.basedOn(estimate.loggedDays, estimate.weighIns, checkIn.weeks).text}
          {thin ? ` ${thin}` : ""}
        </p>
      </section>

      <section aria-label={t.progress.text} {...stylex.props(styles.block)}>
        <h2 {...stylex.props(styles.label)}>{t.progress.text}</h2>
        <dl {...stylex.props(styles.facts)}>
          <div {...stylex.props(styles.fact)}>
            <dt {...stylex.props(styles.term)}>{t.expected.text}</dt>
            <dd {...stylex.props(styles.value)}>
              {perWeek(proposal.expectedWeeklyChangeKg, unit)}
            </dd>
          </div>
          <div {...stylex.props(styles.fact)}>
            <dt {...stylex.props(styles.term)}>{t.actual.text}</dt>
            <dd {...stylex.props(styles.value)}>
              {proposal.actualWeeklyChangeKg === null
                ? t.noTrend.text
                : perWeek(proposal.actualWeeklyChangeKg, unit)}
            </dd>
          </div>
        </dl>
      </section>

      <section aria-label={t.targets.text} {...stylex.props(styles.block)}>
        <h2 {...stylex.props(styles.label)}>{t.targets.text}</h2>
        <table {...stylex.props(styles.table)}>
          <thead>
            <tr>
              <th scope="col" {...stylex.props(styles.th, styles.first)}>
                <span {...stylex.props(styles.srOnly)}>{t.targets.text}</span>
              </th>
              <th scope="col" {...stylex.props(styles.th)}>
                {t.now.text}
              </th>
              <th scope="col" {...stylex.props(styles.th)}>
                {t.proposed.text}
              </th>
            </tr>
          </thead>
          <tbody>
            {MACROS.map(({ key, tint, unit: u }) => (
              <tr key={key}>
                <th scope="row" {...stylex.props(styles.rowHead)}>
                  {tint ? (
                    <span aria-hidden="true" {...stylex.props(styles.dot, styles.tint(tint))} />
                  ) : null}
                  {copy.tracker.macroNames[key].text}
                </th>
                <td {...stylex.props(styles.cell)}>
                  {targets[key].toLocaleString()} {u}
                </td>
                <td {...stylex.props(styles.cell, styles.proposed)}>
                  {proposal.targets[key].toLocaleString()} {u}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {proposal.floored ? <p {...stylex.props(styles.note)}>{t.floored.text}</p> : null}
        {unchanged ? <p {...stylex.props(styles.note)}>{t.unchanged.text}</p> : null}
      </section>

      {anyHandSet ? (
        <label {...stylex.props(styles.keep)}>
          <input
            type="checkbox"
            checked={keepOverrides}
            onChange={(e) => setKeepOverrides(e.target.checked)}
            {...stylex.props(styles.check)}
          />
          <span {...stylex.props(styles.keepText)}>
            {t.keepHandSet.text}
            <span {...stylex.props(styles.note)}>{t.keepHandSetHint.text}</span>
          </span>
        </label>
      ) : null}

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      <div {...stylex.props(styles.actions)}>
        <Button disabled={save.isPending} onClick={() => save.mutate(true)}>
          {save.isPending && save.variables ? t.accepting.text : t.accept.text}
        </Button>
        <Button variant="secondary" disabled={save.isPending} onClick={() => save.mutate(false)}>
          {t.notNow.text}
        </Button>
      </div>
    </>
  );
}

const phone = "@media (max-width: 767px)";

const styles = stylex.create({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: { default: 20, [phone]: 16 },
    maxWidth: 640,
    width: "100%",
  },
  block: {
    display: "flex",
    flexDirection: "column",
    gap: 8,
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
  },
  label: { margin: 0, fontSize: 13, fontWeight: 600, color: colors.subtext },
  big: {
    margin: 0,
    fontFamily: fonts.mono,
    fontSize: 32,
    fontWeight: 600,
    color: colors.ink,
    fontVariantNumeric: "tabular-nums",
  },
  bigUnit: { fontSize: 14, fontWeight: 400, color: colors.subtext },
  note: { margin: 0, fontSize: 13, lineHeight: 1.5, color: colors.subtext },
  facts: { margin: 0, display: "flex", flexWrap: "wrap", gap: 24 },
  fact: { display: "flex", flexDirection: "column", gap: 2 },
  term: { fontSize: 12, color: colors.subtext },
  value: {
    margin: 0,
    fontFamily: fonts.mono,
    fontSize: 16,
    color: colors.ink,
    fontVariantNumeric: "tabular-nums",
  },
  table: { width: "100%", borderCollapse: "collapse" },
  th: { paddingBlock: 6, fontSize: 12, fontWeight: 600, textAlign: "end", color: colors.subtext },
  first: { textAlign: "start", width: "40%" },
  rowHead: {
    paddingBlock: 8,
    fontSize: 14,
    fontWeight: 500,
    textAlign: "start",
    color: colors.ink,
    borderTopWidth: 1,
    borderTopStyle: "solid",
    borderTopColor: colors.surface0,
  },
  cell: {
    paddingBlock: 8,
    textAlign: "end",
    fontFamily: fonts.mono,
    fontSize: 14,
    color: colors.subtext,
    fontVariantNumeric: "tabular-nums",
    borderTopWidth: 1,
    borderTopStyle: "solid",
    borderTopColor: colors.surface0,
    whiteSpace: "nowrap",
  },
  proposed: { color: colors.ink, fontWeight: 600 },
  dot: { display: "inline-block", width: 8, height: 8, marginInlineEnd: 8, borderRadius: 999 },
  tint: (backgroundColor: string) => ({ backgroundColor }),
  keep: { display: "flex", alignItems: "flex-start", gap: 10, cursor: "pointer" },
  check: { width: 18, height: 18, marginTop: 2, accentColor: colors.heat },
  keepText: { display: "flex", flexDirection: "column", gap: 2, fontSize: 15, color: colors.ink },
  actions: { display: "flex", flexWrap: "wrap", gap: 8 },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clip: "rect(0 0 0 0)",
    whiteSpace: "nowrap",
  },
});
