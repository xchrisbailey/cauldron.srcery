import * as stylex from "@stylexjs/stylex";
import {
  type ActivityLevel,
  ACTIVITY_LEVELS,
  addDays,
  ageOn,
  BodyProfile,
  CALCULATOR_LIMITS,
  calculateTargets,
  copy,
  fromKg,
  type Goal,
  GOALS,
  type HeightUnit,
  LocalDate,
  type Sex,
  SEXES,
  TargetsInput,
  TRACKER_LIMITS,
  toKg,
  type TrackerSettings,
  type WeighIn,
  type WeightUnit,
  WeighInInput,
  roundWeight,
} from "@cauldron/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { type FormEvent, Fragment, useEffect, useRef, useState } from "react";
import { ChoiceList, Pills } from "../../../components/Choices";
import { Button, FormMessage, Input, PageHeader, Skeleton, useToast } from "../../../components/ui";
import { control } from "../../../components/ui/controls";
import { messageOr } from "../../../lib/api-failure";
import { pageTitle } from "../../../lib/page-title";
import { localToday } from "../../../lib/recipes";
import {
  defaultRate,
  firstIssue,
  heightFields,
  heightToCm,
  nearestRate,
  type Overrides,
  parseNumber,
  rateChoices,
  resolveTargets,
  showNumber,
  showWeight,
  TARGET_KEYS,
  type TargetKey,
} from "../../../lib/targets";
import { settingsQuery, trackerApi, trackerKeys, weighInsQuery } from "../../../lib/tracker";
import { colors, fonts } from "../../../styles/tokens.stylex";

// Set your targets (#112): body stats, activity and a goal go in, daily
// calories and macros come out with the reasoning shown, and any of them can
// be overridden by hand. Three short steps the first time; with a profile it
// opens on the targets, with the profile as an editable summary.

const t = copy.tracker.targets;
const STEPS = 3;

export const Route = createFileRoute("/_authed/tracker/targets")({
  head: () => pageTitle(t.pageTitle),
  component: TargetsPage,
});

function TargetsPage() {
  const today = localToday();
  const settings = useQuery(settingsQuery());
  const weighIns = useQuery(weighInsQuery(addDays(today, -365), today));

  if (settings.isError || weighIns.isError) {
    return (
      <Page>
        <FormMessage tone="error">{t.couldntLoad.text}</FormMessage>
        <div>
          <Button
            variant="secondary"
            onClick={() => {
              void settings.refetch();
              void weighIns.refetch();
            }}
          >
            {copy.ui.tryAgain.text}
          </Button>
        </div>
      </Page>
    );
  }
  if (!settings.data || !weighIns.data) {
    return (
      <Page>
        <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.stack)}>
          <Skeleton height={20} width="30%" />
          <Skeleton height={44} />
          <Skeleton height={44} />
          <Skeleton height={44} width="60%" />
        </div>
      </Page>
    );
  }
  const latest = [...weighIns.data].sort((a, b) => b.date.localeCompare(a.date))[0] ?? null;
  return (
    <Page>
      <Flow settings={settings.data} latest={latest} today={today} />
    </Page>
  );
}

function Page({ children }: { children: React.ReactNode }) {
  return (
    <div {...stylex.props(styles.page)}>
      <PageHeader title={t.title.text} />
      {children}
    </div>
  );
}

interface Values {
  sex: Sex | null;
  birthDate: string;
  heightUnit: HeightUnit;
  cm: string;
  feet: string;
  inches: string;
  weightUnit: WeightUnit;
  weight: string;
  activity: ActivityLevel;
  goal: Goal;
  /** In the weight unit, e.g. 0.5 kg or 1 lb a week; null when maintaining. */
  rate: number | null;
  proteinPerKg: string;
  fatPercent: string;
  overrides: Overrides;
}

const initialValues = (settings: TrackerSettings, latest: WeighIn | null): Values => {
  const { profile, targets } = settings;
  if (!profile) {
    return {
      sex: null,
      birthDate: "",
      heightUnit: "cm",
      cm: "",
      feet: "",
      inches: "",
      weightUnit: "kg",
      weight: "",
      activity: "light",
      goal: "maintain",
      rate: null,
      proteinPerKg: showNumber(CALCULATOR_LIMITS.proteinPerKg.default),
      fatPercent: showNumber(CALCULATOR_LIMITS.fatShare.default * 100, 0),
      overrides: {},
    };
  }
  const overrides: Overrides = {};
  if (targets)
    for (const key of TARGET_KEYS)
      if (targets.overridden[key]) overrides[key] = String(targets[key]);
  return {
    sex: profile.sex,
    birthDate: profile.birthDate,
    heightUnit: profile.heightUnit,
    ...heightFields(profile.heightCm),
    weightUnit: profile.weightUnit,
    weight: latest ? showWeight(latest.weightKg, profile.weightUnit) : "",
    activity: profile.activity,
    goal: profile.goal,
    rate: nearestRate(profile.goal, profile.weightUnit, profile.weeklyRateKg),
    proteinPerKg: showNumber(profile.proteinPerKg),
    fatPercent: showNumber(profile.fatShare * 100, 0),
    overrides,
  };
};

const weightKgOf = (v: Values): number | null => {
  const n = parseNumber(v.weight);
  return n === null ? null : toKg(n, v.weightUnit);
};

/** Messages for step one; empty when it's good. */
const aboutErrors = (v: Values, today: string) => {
  const errors: { sex?: string; birthDate?: string; height?: string; weight?: string } = {};
  if (v.sex === null) errors.sex = copy.validation.required.text;
  if (v.birthDate === "") errors.birthDate = copy.validation.required.text;
  else if (firstIssue(LocalDate, v.birthDate) || v.birthDate > today || v.birthDate < "1900-01-01")
    errors.birthDate = copy.validation.date.text;
  const cm = heightToCm(v.heightUnit, v);
  if (cm === null) errors.height = copy.validation.required.text;
  else if (firstIssue(BodyProfile.fields.heightCm, cm))
    errors.height = copy.validation.numberBetween(
      TRACKER_LIMITS.heightCm.min,
      TRACKER_LIMITS.heightCm.max,
    ).text;
  const kg = weightKgOf(v);
  if (kg === null) errors.weight = copy.validation.required.text;
  else if (firstIssue(WeighInInput, { weightKg: kg }))
    errors.weight = copy.validation.numberBetween(
      roundWeight(fromKg(TRACKER_LIMITS.weightKg.min, v.weightUnit)),
      roundWeight(fromKg(TRACKER_LIMITS.weightKg.max, v.weightUnit)),
    ).text;
  return errors;
};

const adjustErrors = (v: Values) => {
  const protein = parseNumber(v.proteinPerKg);
  const fat = parseNumber(v.fatPercent);
  const errors: { proteinPerKg?: string; fatPercent?: string } = {};
  if (protein === null || firstIssue(BodyProfile.fields.proteinPerKg, protein) !== undefined)
    errors.proteinPerKg = copy.validation.numberBetween(
      TRACKER_LIMITS.proteinPerKg.min,
      TRACKER_LIMITS.proteinPerKg.max,
    ).text;
  if (fat === null || firstIssue(BodyProfile.fields.fatShare, fat / 100) !== undefined)
    errors.fatPercent = copy.validation.numberBetween(
      TRACKER_LIMITS.fatShare.min * 100,
      TRACKER_LIMITS.fatShare.max * 100,
    ).text;
  return errors;
};

const rowErrors = (v: Values): Partial<Record<TargetKey, string>> => {
  const errors: Partial<Record<TargetKey, string>> = {};
  for (const key of TARGET_KEYS) {
    const typed = v.overrides[key];
    if (typed === undefined) continue;
    const n = parseNumber(typed);
    const issue = firstIssue(TargetsInput.fields[key], n ?? Number.NaN);
    if (issue !== undefined || n === null) errors[key] = issue ?? copy.validation.required.text;
  }
  return errors;
};

const whole = (n: number) => Math.round(n).toLocaleString();

function Flow({
  settings,
  latest,
  today,
}: {
  settings: TrackerSettings;
  latest: WeighIn | null;
  today: string;
}) {
  const queryClient = useQueryClient();
  const toast = useToast();
  const navigate = useNavigate();
  const [v, setV] = useState(() => initialValues(settings, latest));
  const [step, setStep] = useState(settings.profile && latest ? 2 : 0);
  const [attempted, setAttempted] = useState(false);
  const [settled, setSettled] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const first = useRef(true);

  useEffect(() => {
    if (first.current) first.current = false;
    else heading.current?.focus();
  }, [step]);

  const update = (patch: Partial<Values>) => {
    setV((old) => ({ ...old, ...patch }));
    setSettled(false);
    setError(null);
  };

  const about = aboutErrors(v, today);
  const adjust = adjustErrors(v);
  const aboutOk = Object.keys(about).length === 0;
  const weightKg = weightKgOf(v);
  const cm = heightToCm(v.heightUnit, v);
  const proteinPerKg = adjust.proteinPerKg ? undefined : (parseNumber(v.proteinPerKg) ?? undefined);
  const fatShare = adjust.fatPercent ? undefined : (parseNumber(v.fatPercent) ?? 0) / 100;
  const rateKg = v.rate === null ? 0 : toKg(v.rate, v.weightUnit);

  const calc =
    aboutOk && v.sex !== null && weightKg !== null && cm !== null
      ? calculateTargets({
          sex: v.sex,
          birthDate: v.birthDate,
          heightCm: cm,
          weightKg,
          activity: v.activity,
          goal: v.goal,
          weeklyRateKg: rateKg,
          proteinPerKg,
          fatShare: fatShare === 0 ? undefined : fatShare,
          today,
        })
      : null;
  const resolved =
    calc && weightKg !== null
      ? resolveTargets({
          calculated: calc.targets,
          overrides: v.overrides,
          weightKg: calc.adjustedWeightKg,
          proteinPerKg,
          fatShare: fatShare === 0 ? undefined : fatShare,
        })
      : null;
  const targetErrors = rowErrors(v);

  const save = useMutation({
    mutationFn: async (p: {
      profile: BodyProfile;
      weighInKg: number | null;
      targets: TargetsInput;
    }) => {
      await trackerApi.saveProfile(p.profile);
      if (p.weighInKg !== null) await trackerApi.weighIn(today, p.weighInKg);
      await trackerApi.saveTargets(p.targets);
    },
    onSuccess: () => {
      setSettled(true);
      toast(t.saved.text);
      void navigate({ to: "/tracker" });
    },
    onError: (e) => setError(messageOr(e, t.couldntSave.text)),
    onSettled: () => queryClient.invalidateQueries({ queryKey: trackerKeys.all }),
  });

  const goTo = (next: number) => {
    setAttempted(false);
    setStep(next);
  };

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (step === 0) {
      setAttempted(true);
      if (aboutOk) goTo(1);
      return;
    }
    if (step === 1) return goTo(2);
    setAttempted(true);
    if (!calc || !resolved || weightKg === null || cm === null || v.sex === null) return;
    if (Object.keys(adjust).length > 0 || Object.keys(targetErrors).length > 0) return;
    const profile = {
      sex: v.sex,
      birthDate: v.birthDate,
      heightCm: Math.round(cm * 10) / 10,
      activity: v.activity,
      goal: v.goal,
      weeklyRateKg: Math.round(calc.weeklyRateKg * 1000) / 1000,
      proteinPerKg: proteinPerKg ?? CALCULATOR_LIMITS.proteinPerKg.default,
      fatShare: fatShare ?? CALCULATOR_LIMITS.fatShare.default,
      weightUnit: v.weightUnit,
      heightUnit: v.heightUnit,
    };
    const targets = { ...resolved.values, overridden: resolved.overridden };
    // Only weigh in when the weight is new or changed, in the unit it was shown in.
    const unchanged =
      latest !== null &&
      showWeight(latest.weightKg, v.weightUnit) === showNumber(roundWeight(parseNumber(v.weight)!));
    const rounded = Math.round(weightKg * 100) / 100;
    if (
      firstIssue(BodyProfile, profile) !== undefined ||
      firstIssue(TargetsInput, targets) !== undefined
    )
      return setError(t.fixThese.text);
    save.mutate({
      profile: profile as BodyProfile,
      weighInKg: unchanged ? null : rounded,
      targets,
    });
  };

  return (
    <form onSubmit={onSubmit} noValidate {...stylex.props(styles.stack)}>
      <div {...stylex.props(styles.stepHeader)}>
        <span {...stylex.props(styles.mono, styles.stepCount)}>{t.step(step + 1, STEPS).text}</span>
        <h2 ref={heading} tabIndex={-1} {...stylex.props(styles.stepTitle)}>
          {[t.steps.about, t.steps.activity, t.steps.targets][step]!.text}
        </h2>
      </div>

      {step === 0 ? (
        <AboutStep v={v} update={update} errors={attempted ? about : {}} today={today} />
      ) : null}
      {step === 1 ? <ActivityStep v={v} update={update} /> : null}
      {step === 2 ? (
        calc && resolved ? (
          <TargetsStep
            v={v}
            update={update}
            calc={calc}
            resolved={resolved}
            errors={attempted ? { ...targetErrors } : {}}
            adjustErrors={attempted ? adjust : {}}
            cm={cm}
            today={today}
            goTo={goTo}
          />
        ) : (
          <FormMessage tone="error">{t.fixThese.text}</FormMessage>
        )
      ) : null}

      {error ? <FormMessage tone="error">{error}</FormMessage> : null}
      {settled ? <FormMessage tone="info">{t.settled.text}</FormMessage> : null}

      <div {...stylex.props(styles.actions)}>
        {step > 0 ? (
          <Button variant="secondary" onClick={() => goTo(step - 1)}>
            {t.back.text}
          </Button>
        ) : null}
        {step < 2 ? (
          <Button type="submit">{t.continue.text}</Button>
        ) : (
          <Button type="submit" disabled={save.isPending || !calc}>
            {save.isPending ? t.saving.text : t.save.text}
          </Button>
        )}
      </div>
    </form>
  );
}

type Update = (patch: Partial<Values>) => void;

function AboutStep({
  v,
  update,
  errors,
  today,
}: {
  v: Values;
  update: Update;
  errors: ReturnType<typeof aboutErrors>;
  today: string;
}) {
  const switchHeight = (heightUnit: HeightUnit) => {
    const cm = heightToCm(v.heightUnit, v);
    update({ heightUnit, ...(cm !== null ? heightFields(cm) : {}) });
  };
  const switchWeight = (weightUnit: WeightUnit) => {
    const n = parseNumber(v.weight);
    update({
      weightUnit,
      weight: n === null ? v.weight : showWeight(toKg(n, v.weightUnit), weightUnit),
      rate: v.goal === "maintain" ? null : defaultRate(v.goal, weightUnit),
    });
  };
  return (
    <div {...stylex.props(styles.stack)}>
      <Pills
        legend={t.sex.text}
        value={v.sex}
        onChange={(sex) => update({ sex })}
        options={SEXES.map((value) => ({ value, label: t.sexes[value].text }))}
        error={errors.sex}
      />
      <Input
        label={t.birthDate.text}
        type="date"
        value={v.birthDate}
        max={today}
        min="1900-01-01"
        autoComplete="bday"
        error={errors.birthDate}
        hint={t.sexHint.text}
        xstyle={styles.mono}
        onChange={(e) => update({ birthDate: e.target.value })}
      />
      <div {...stylex.props(styles.stack)}>
        <div {...stylex.props(styles.labelRow)}>
          <span {...stylex.props(styles.label)}>{t.height.text}</span>
          <Pills
            small
            mono
            hideLegend
            legend={t.unitSwitch(t.height.text).text}
            value={v.heightUnit}
            onChange={switchHeight}
            options={(["cm", "ftin"] as const).map((value) => ({
              value,
              label: t.heightUnits[value].text,
            }))}
          />
        </div>
        {v.heightUnit === "cm" ? (
          <NumberInput
            label={t.height.text}
            hideLabel
            unit={t.heightUnits.cm.text}
            value={v.cm}
            onChange={(cm) => update({ cm })}
            error={errors.height}
            autoComplete="off"
          />
        ) : (
          <div {...stylex.props(styles.pair)}>
            <NumberInput
              label={t.feet.text}
              unit={t.feet.text}
              value={v.feet}
              onChange={(feet) => update({ feet })}
              error={errors.height}
              inputMode="numeric"
            />
            <NumberInput
              label={t.inches.text}
              unit={t.inches.text}
              value={v.inches}
              onChange={(inches) => update({ inches })}
            />
          </div>
        )}
      </div>
      <div {...stylex.props(styles.stack)}>
        <div {...stylex.props(styles.labelRow)}>
          <span {...stylex.props(styles.label)}>{t.weight.text}</span>
          <Pills
            small
            mono
            hideLegend
            legend={t.unitSwitch(t.weight.text).text}
            value={v.weightUnit}
            onChange={switchWeight}
            options={WEIGHT_UNIT_OPTIONS}
          />
        </div>
        <NumberInput
          label={t.weight.text}
          hideLabel
          unit={t.weightUnits[v.weightUnit].text}
          value={v.weight}
          onChange={(weight) => update({ weight })}
          error={errors.weight}
        />
      </div>
    </div>
  );
}

const WEIGHT_UNIT_OPTIONS = (["kg", "lb"] as const).map((value) => ({
  value,
  label: t.weightUnits[value].text,
}));

function ActivityStep({ v, update }: { v: Values; update: Update }) {
  const choices = rateChoices(v.goal, v.weightUnit);
  const unit = t.weightUnits[v.weightUnit].text;
  return (
    <div {...stylex.props(styles.stack)}>
      <ChoiceList
        legend={t.activity.text}
        value={v.activity}
        onChange={(activity) => update({ activity })}
        options={ACTIVITY_LEVELS.map((value) => ({
          value,
          label: t.activityLevels[value].label.text,
          hint: t.activityLevels[value].hint.text,
        }))}
      />
      <Pills
        legend={t.goal.text}
        value={v.goal}
        onChange={(goal) => update({ goal, rate: defaultRate(goal, v.weightUnit) })}
        options={GOALS.map((value) => ({ value, label: t.goals[value].text }))}
      />
      {choices.length > 0 ? (
        <Pills
          mono
          legend={t.rate.text}
          value={v.rate === null ? null : String(v.rate)}
          onChange={(rate) => update({ rate: Number(rate) })}
          options={choices.map((c) => ({
            value: String(c.amount),
            label: t.perWeek(String(c.amount), unit).text,
          }))}
        />
      ) : null}
    </div>
  );
}

function TargetsStep({
  v,
  update,
  calc,
  resolved,
  errors,
  adjustErrors: adjust,
  cm,
  today,
  goTo,
}: {
  v: Values;
  update: Update;
  calc: NonNullable<ReturnType<typeof calculateTargets>>;
  resolved: NonNullable<ReturnType<typeof resolveTargets>>;
  errors: Partial<Record<TargetKey, string>>;
  adjustErrors: ReturnType<typeof adjustErrors>;
  cm: number | null;
  today: string;
  goTo: (step: number) => void;
}) {
  const unit = t.weightUnits[v.weightUnit].text;
  const rate = v.rate === null ? "" : String(v.rate);
  const adjustment = Math.abs(calc.dailyAdjustment);
  const setTarget = (key: TargetKey, text: string) =>
    update({ overrides: { ...v.overrides, [key]: text } });
  const resetTarget = (key: TargetKey) => {
    const { [key]: _gone, ...rest } = v.overrides;
    update({ overrides: rest });
  };
  const summary = [
    t.sexes[v.sex!].text,
    t.summaryAge(ageOn(v.birthDate, today)).text,
    v.heightUnit === "cm"
      ? `${showNumber(cm ?? 0)} ${t.heightUnits.cm.text}`
      : `${v.feet} ${t.feet.text} ${v.inches || "0"} ${t.inches.text}`,
    `${v.weight} ${unit}`,
  ].join(" · ");
  const lifestyle = [
    t.activityLevels[v.activity].label.text,
    v.goal === "maintain"
      ? t.goals.maintain.text
      : `${t.goals[v.goal].text}, ${t.perWeek(rate, unit).text}`,
  ].join(" · ");

  return (
    <div {...stylex.props(styles.stack)}>
      <dl {...stylex.props(styles.summary)}>
        <SummaryRow label={t.steps.about.text} value={summary} onEdit={() => goTo(0)} />
        <SummaryRow label={t.steps.activity.text} value={lifestyle} onEdit={() => goTo(1)} />
      </dl>

      <section aria-label={t.steps.targets.text} {...stylex.props(styles.reasoning)}>
        <p {...stylex.props(styles.headline)}>
          <Numbers text={t.headline(v.goal, whole(calc.targets.calories), rate, unit).text} />
        </p>
        <p {...stylex.props(styles.note)}>
          <Numbers
            text={
              t.breakdown(
                whole(calc.restingEnergy),
                whole(calc.activityEnergy),
                whole(calc.expenditure),
              ).text
            }
          />
          {adjustment >= 1 ? (
            <>
              {" "}
              <Numbers
                text={
                  calc.dailyAdjustment < 0
                    ? t.adjustLose(whole(adjustment)).text
                    : t.adjustGain(whole(adjustment)).text
                }
              />
            </>
          ) : null}
          {calc.adjustedWeightKg < (weightKgOf(v) ?? 0) - 0.5 ? (
            <>
              {" "}
              <Numbers
                text={
                  t.adjustedWeight(
                    showNumber(roundWeight(fromKg(calc.adjustedWeightKg, v.weightUnit))),
                    unit,
                  ).text
                }
              />
            </>
          ) : null}
          {calc.floored ? (
            <>
              {" "}
              <Numbers text={t.floor(whole(calc.targets.calories)).text} />
            </>
          ) : null}
        </p>
      </section>

      <div {...stylex.props(styles.targets)}>
        {TARGET_KEYS.map((key) => {
          const label = t.macroLabels[key].text;
          const unitText = key === "calories" ? t.unitKcal.text : t.unitGrams.text;
          const overridden = resolved.overridden[key];
          const shown = overridden ? (v.overrides[key] ?? "") : String(resolved.values[key]);
          const message = errors[key];
          return (
            <div key={key} {...stylex.props(styles.targetRow)}>
              <span {...stylex.props(styles.targetLabel)}>
                <span
                  aria-hidden="true"
                  {...stylex.props(styles.dot, key === "calories" ? styles.noDot : dots[key])}
                />
                {label}
              </span>
              <span {...stylex.props(styles.targetInput)}>
                <input
                  aria-label={label}
                  aria-invalid={message ? true : undefined}
                  inputMode="numeric"
                  autoComplete="off"
                  value={shown}
                  onChange={(e) => setTarget(key, e.target.value)}
                  {...stylex.props(
                    control.field,
                    styles.mono,
                    styles.targetField,
                    message ? control.invalid : null,
                  )}
                />
                <span {...stylex.props(styles.mono, styles.unit)}>{unitText}</span>
              </span>
              <span {...stylex.props(styles.status)}>
                {overridden ? (
                  <>
                    <span>{t.setByYou.text}</span>
                    <Button
                      variant="ghost"
                      aria-label={t.resetLabel(label.toLowerCase()).text}
                      onClick={() => resetTarget(key)}
                    >
                      {t.reset.text}
                    </Button>
                  </>
                ) : (
                  <span>{t.calculated.text}</span>
                )}
              </span>
              {message ? <span {...stylex.props(styles.rowError)}>{message}</span> : null}
            </div>
          );
        })}
      </div>

      <details {...stylex.props(styles.details)} open={Object.keys(adjust).length > 0 || undefined}>
        <summary {...stylex.props(styles.summaryToggle)}>{t.adjust.text}</summary>
        <div {...stylex.props(styles.pair)}>
          <Input
            label={t.proteinPerKg.text}
            inputMode="decimal"
            autoComplete="off"
            value={v.proteinPerKg}
            error={adjust.proteinPerKg}
            xstyle={styles.mono}
            onChange={(e) => update({ proteinPerKg: e.target.value })}
          />
          <Input
            label={t.fatShare.text}
            inputMode="numeric"
            autoComplete="off"
            value={v.fatPercent}
            error={adjust.fatPercent}
            xstyle={styles.mono}
            onChange={(e) => update({ fatPercent: e.target.value })}
          />
        </div>
      </details>
    </div>
  );
}

function SummaryRow({
  label,
  value,
  onEdit,
}: {
  label: string;
  value: string;
  onEdit: () => void;
}) {
  return (
    <div {...stylex.props(styles.summaryRow)}>
      <div {...stylex.props(styles.summaryText)}>
        <dt {...stylex.props(styles.summaryLabel)}>{label}</dt>
        <dd {...stylex.props(styles.summaryValue)}>
          <Numbers text={value} />
        </dd>
      </div>
      <Button variant="ghost" aria-label={`${t.edit.text}: ${label}`} onClick={onEdit}>
        {t.edit.text}
      </Button>
    </div>
  );
}

/** A sentence with its numbers set in Geist Mono. */
function Numbers({ text }: { text: string }) {
  return (
    <>
      {text.split(/(\d[\d,.]*)/).map((part, i) =>
        i % 2 === 1 ? (
          <span key={i} {...stylex.props(styles.mono)}>
            {part}
          </span>
        ) : (
          <Fragment key={i}>{part}</Fragment>
        ),
      )}
    </>
  );
}

function NumberInput({
  label,
  hideLabel = false,
  unit,
  value,
  onChange,
  error,
  inputMode = "decimal",
  autoComplete,
}: {
  label: string;
  hideLabel?: boolean;
  unit: string;
  value: string;
  onChange: (value: string) => void;
  error?: string | undefined;
  inputMode?: "decimal" | "numeric";
  autoComplete?: string;
}) {
  return (
    <div {...stylex.props(styles.numberInput)}>
      <Input
        label={label}
        hideLabel={hideLabel}
        error={error}
        inputMode={inputMode}
        autoComplete={autoComplete ?? "off"}
        value={value}
        xstyle={styles.mono}
        onChange={(e) => onChange(e.target.value)}
      />
      <span {...stylex.props(styles.mono, styles.inlineUnit)}>{unit}</span>
    </div>
  );
}

const phone = "@media (max-width: 767px)";

const dots = stylex.create({
  protein: { backgroundColor: colors.trackerBlue },
  carbs: { backgroundColor: colors.trackerTeal },
  fat: { backgroundColor: colors.trackerRed },
});

const styles = stylex.create({
  page: {
    display: "flex",
    flexDirection: "column",
    gap: 20,
    width: "100%",
    maxWidth: 560,
    marginInline: "auto",
  },
  stack: { display: "flex", flexDirection: "column", gap: 16 },
  stepHeader: { display: "flex", flexDirection: "column", gap: 4 },
  stepCount: { fontSize: 12, color: colors.overlay1, letterSpacing: "0.04em" },
  stepTitle: {
    margin: 0,
    fontSize: 20,
    fontWeight: 650,
    letterSpacing: "-0.01em",
    outline: "none",
  },
  mono: { fontFamily: fonts.mono, fontVariantNumeric: "tabular-nums" },
  label: { fontSize: 14, fontWeight: 500, color: colors.subtext },
  labelRow: { display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 },
  pair: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr",
    gap: 12,
  },
  numberInput: { position: "relative" },
  inlineUnit: {
    position: "absolute",
    insetInlineEnd: 12,
    bottom: 11,
    fontSize: 13,
    color: colors.overlay1,
    pointerEvents: "none",
  },
  actions: { display: "flex", flexWrap: "wrap", gap: 8, paddingBlock: 4 },
  summary: {
    display: "flex",
    flexDirection: "column",
    margin: 0,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
  },
  summaryRow: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    paddingBlock: 8,
    paddingInline: 14,
    borderTopWidth: { default: 1, ":first-child": 0 },
    borderTopStyle: "solid",
    borderTopColor: colors.surface0,
  },
  summaryText: { minWidth: 0 },
  summaryLabel: { fontSize: 12, color: colors.overlay1 },
  summaryValue: { margin: 0, fontSize: 14, color: colors.ink },
  reasoning: {
    display: "flex",
    flexDirection: "column",
    gap: 6,
    paddingBlock: 14,
    paddingInline: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
  },
  headline: { margin: 0, fontSize: 17, fontWeight: 600, color: colors.ink, lineHeight: 1.35 },
  note: { margin: 0, fontSize: 13, lineHeight: 1.5, color: colors.subtext },
  targets: { display: "flex", flexDirection: "column", gap: 10 },
  targetRow: {
    display: "grid",
    gridTemplateColumns: { default: "110px auto 1fr", [phone]: "1fr auto" },
    alignItems: "center",
    columnGap: 12,
    rowGap: 4,
  },
  targetLabel: {
    display: "inline-flex",
    alignItems: "center",
    gap: 8,
    fontSize: 15,
    color: colors.ink,
  },
  dot: { width: 8, height: 8, borderRadius: 999, flexShrink: 0 },
  noDot: { backgroundColor: colors.magic },
  targetInput: { display: "inline-flex", alignItems: "center", gap: 8 },
  targetField: { width: 104, textAlign: "end" },
  unit: { fontSize: 13, color: colors.overlay1 },
  status: {
    display: "inline-flex",
    alignItems: "center",
    gap: 4,
    gridColumn: { default: "auto", [phone]: "1 / -1" },
    fontSize: 13,
    color: colors.subtext,
    minHeight: 40,
  },
  rowError: { gridColumn: "1 / -1", fontSize: 13, fontWeight: 500, color: colors.ink },
  details: { fontSize: 14 },
  summaryToggle: {
    cursor: "pointer",
    paddingBlock: 8,
    fontWeight: 500,
    color: colors.ink,
    marginBottom: 8,
  },
});
