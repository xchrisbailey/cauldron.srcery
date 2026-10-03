import {
  addDays,
  ADAPTIVE_LIMITS,
  calculateTargets,
  daysBetween,
  estimateExpenditure,
  type ExpenditureEstimate,
  type IntakeDay,
  proposeTargets,
  type ProposedTargets,
  type Targets,
  type TrackerSettings,
  trendSeries,
  type WeighIn,
} from "@cauldron/shared";

// Pure helpers behind the weekly check-in (#118): when it's due, and what the
// intake and weight trend say about the targets.

/** Days between check-ins. */
export const CHECK_IN_INTERVAL_DAYS = 7;

/** The first day the check-in looks at: the start of the estimate's window. */
export const checkInFrom = (today: string): string =>
  addDays(today, -(ADAPTIVE_LIMITS.windowDays - 1));

/** At least two weigh-ins, a week or more apart. */
export const hasWeekOfData = (weighInDates: ReadonlyArray<string>): boolean => {
  if (weighInDates.length < 2) return false;
  const sorted = [...weighInDates].sort();
  return daysBetween(sorted[0]!, sorted[sorted.length - 1]!) >= CHECK_IN_INTERVAL_DAYS;
};

/** Whether to offer the check-in: targets and a profile, a week since the last, a week of data. */
export const isCheckInDue = (input: {
  readonly settings: Pick<TrackerSettings, "profile"> & {
    readonly targets: Pick<Targets, "checkedInOn"> | null;
  };
  readonly weighIns: ReadonlyArray<Pick<WeighIn, "date">>;
  readonly today: string;
}): boolean => {
  const { profile, targets } = input.settings;
  if (!profile || !targets) return false;
  const last = targets.checkedInOn;
  if (last !== null && daysBetween(last, input.today) < CHECK_IN_INTERVAL_DAYS) return false;
  // Only weigh-ins in the estimate's window count, so an old pair doesn't
  // keep offering a check-in the estimate can't use.
  const from = checkInFrom(input.today);
  return hasWeekOfData(
    input.weighIns.map((w) => w.date).filter((d) => d >= from && d <= input.today),
  );
};

/** Days the smoothed trend needs before its changes can be trusted. */
const TREND_WARM_UP_DAYS = 14;

/**
 * The trend the estimate reads. The smoothed trend starts at the first
 * weigh-in and lags for a couple of weeks, which would understate a new
 * cook's change; until it has warmed up, a straight-line fit through the
 * window's weigh-ins stands in for it.
 */
export const trendForEstimate = (
  weighIns: ReadonlyArray<WeighIn>,
  today: string,
): ReadonlyArray<{ readonly date: string; readonly trendKg: number }> => {
  const series = trendSeries(weighIns);
  const first = series[0];
  const from = checkInFrom(today);
  if (!first || daysBetween(first.date, from) >= TREND_WARM_UP_DAYS) {
    return series.map((p) => ({ date: p.date, trendKg: p.trendKg }));
  }
  const inWindow = series.filter((p) => p.date >= from && p.date <= today);
  if (inWindow.length < 2) return inWindow.map((p) => ({ date: p.date, trendKg: p.weightKg }));
  const xs = inWindow.map((p) => daysBetween(from, p.date));
  const mx = xs.reduce((a, b) => a + b, 0) / xs.length;
  const my = inWindow.reduce((a, p) => a + p.weightKg, 0) / inWindow.length;
  let sxy = 0;
  let sxx = 0;
  inWindow.forEach((p, i) => {
    sxy += (xs[i]! - mx) * (p.weightKg - my);
    sxx += (xs[i]! - mx) ** 2;
  });
  const slope = sxx === 0 ? 0 : sxy / sxx;
  return inWindow.map((p, i) => ({ date: p.date, trendKg: my + slope * (xs[i]! - mx) }));
};

export interface CheckIn {
  readonly estimate: ExpenditureEstimate;
  readonly proposal: ProposedTargets;
  /** Whole weeks the window covers. */
  readonly weeks: number;
  readonly weightKg: number;
}

/** The estimate and proposal, or null without a profile, targets and a weigh-in. */
export const buildCheckIn = (input: {
  readonly settings: TrackerSettings;
  readonly intake: ReadonlyArray<IntakeDay>;
  readonly weighIns: ReadonlyArray<WeighIn>;
  readonly today: string;
  readonly keepOverrides: boolean;
}): CheckIn | null => {
  const { profile, targets } = input.settings;
  const series = trendSeries(input.weighIns);
  const latest = series[series.length - 1];
  if (!profile || !targets || !latest) return null;
  const weightKg = latest.trendKg;

  const calculator = calculateTargets({
    sex: profile.sex,
    birthDate: profile.birthDate,
    heightCm: profile.heightCm,
    weightKg,
    activity: profile.activity,
    goal: profile.goal,
    weeklyRateKg: profile.weeklyRateKg,
    proteinPerKg: profile.proteinPerKg,
    fatShare: profile.fatShare,
    today: input.today,
  });
  // Only logged days count; an unlogged day is not a zero-calorie day.
  const estimate = estimateExpenditure({
    intake: input.intake.map((d) => ({ date: d.date, calories: d.totals.calories })),
    trend: trendForEstimate(input.weighIns, input.today),
    today: input.today,
    calculatorExpenditure: calculator.expenditure,
  });
  const proposal = proposeTargets({
    estimate,
    goal: profile.goal,
    weeklyRateKg: profile.weeklyRateKg,
    weightKg,
    sex: profile.sex,
    proteinPerKg: profile.proteinPerKg,
    fatShare: profile.fatShare,
    current: targets,
    keepOverrides: input.keepOverrides,
  });
  return {
    estimate,
    proposal,
    weeks: Math.max(1, Math.round(estimate.windowDays / 7)),
    weightKg,
  };
};
