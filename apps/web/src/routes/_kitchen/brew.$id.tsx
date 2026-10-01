import * as stylex from "@stylexjs/stylex";
import {
  copy,
  displayMeasure,
  type Ingredient,
  type Recipe,
  Scale,
  type ScaleSearch,
  stepIngredients,
  type UnitSystemChoice,
} from "@cauldron/shared";
import { useHotkey } from "@tanstack/react-hotkeys";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Fragment, useMemo, useRef, useState } from "react";
import { Button, ButtonLink, EmptyState, Skeleton, useToast } from "../../components/ui";
import { focusRing } from "../../components/ui/controls";
import { localToday, markCooked, recipeQuery, settleRecipe } from "../../lib/recipes";
import {
  chime,
  clock,
  secondsLeft,
  type StepTimer,
  unlockChime,
  useStepTimers,
} from "../../lib/step-timers";
import { useUnitChoice } from "../../lib/units";
import { useWakeLock } from "../../lib/wake-lock";
import { colors, fonts, quantity } from "../../styles/tokens.stylex";

// Start brewing (#20): one step at a time in large type, with the step's
// ingredients and timer. Timers keep running across steps, chime and notify
// when done, and the screen stays awake. Controls are plain: hands are busy.

export const Route = createFileRoute("/_kitchen/brew/$id")({
  validateSearch: (search: Record<string, unknown>): ScaleSearch =>
    Scale.toSearch(Scale.fromSearch(search)),
  component: Brew,
});

function Brew() {
  const { id } = Route.useParams();
  // Mid-cook, the recipe shouldn't change underfoot, and a failed refetch on a
  // patchy kitchen signal mustn't tear down the page (and its timers).
  const recipe = useQuery({ ...recipeQuery(id), staleTime: Infinity, refetchOnWindowFocus: false });
  if (recipe.data) return <Brewing recipe={recipe.data} />;
  if (recipe.isPending) {
    return (
      <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.screen)}>
        <Skeleton height={24} width="50%" />
        <Skeleton height={160} />
      </div>
    );
  }
  return (
    <div {...stylex.props(styles.screen)}>
      <EmptyState
        message={copy.recipeView.notFound.text}
        actions={
          <ButtonLink to="/recipes" variant="secondary">
            {copy.recipeView.backToRecipes.text}
          </ButtonLink>
        }
      />
    </div>
  );
}

/**
 * A system notification when the cook allowed them. Phones only show ones
 * sent through a service worker (Android) or from an installed web app (iOS),
 * so this uses a registered worker when there is one, and otherwise the plain
 * constructor, which desktop browsers support. The toast and chime cover the rest.
 */
const notify = (title: string, body: string, tag: string) => {
  if (typeof Notification === "undefined" || Notification.permission !== "granted") return;
  const direct = () => {
    try {
      new Notification(title, { body, tag });
    } catch {
      // Not allowed outside a service worker here.
    }
  };
  if (!("serviceWorker" in navigator)) return direct();
  void navigator.serviceWorker
    .getRegistration()
    .then(
      (registration) =>
        registration ? registration.showNotification(title, { body, tag }) : direct(),
      direct,
    );
};

/** Numbers, fractions and the measures after them, set in Geist Mono inside a step. */
const MEASURE =
  /((?:\d+(?:[.,]\d+)?|[½¼¾⅓⅔⅛])(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?(?:\s*(?:°\s?[CF]|%|(?:kg|g|ml|l|oz|lbs?|cups?|tbsp|tsp|minutes?|mins?|hours?|hrs?|seconds?|secs?)\b))?)/;

function StepText({ text }: { text: string }) {
  const parts = text.split(new RegExp(MEASURE.source, "gi"));
  return (
    <p {...stylex.props(styles.stepText)}>
      {parts.map((part, i) =>
        i % 2 === 1 ? (
          <span key={i} {...stylex.props(styles.inlineMeasure)}>
            {part}
          </span>
        ) : (
          <Fragment key={i}>{part}</Fragment>
        ),
      )}
    </p>
  );
}

function Brewing({ recipe }: { recipe: Recipe }) {
  const search = Route.useSearch();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const toast = useToast();
  const wake = useWakeLock();
  const [at, setIndex] = useState(0);
  const [units] = useUnitChoice();
  const [busy, setBusy] = useState(false);
  // When the step last changed, so a quick second tap meant for "Next step"
  // doesn't land on "Brewed" as it takes the button's place.
  const movedAt = useRef(0);

  const steps = recipe.steps;
  const count = steps.length;
  const index = Math.min(at, Math.max(0, count - 1));
  const step = steps[index];
  const factor = Scale.factor(Scale.fromSearch(search), recipe.servings);
  const matched = useMemo(
    () => stepIngredients(steps, recipe.ingredients),
    [steps, recipe.ingredients],
  );

  const { timers, now, start, pause, reset } = useStepTimers((done) => {
    chime();
    navigator.vibrate?.([200, 100, 200]);
    const text = copy.brewing.timerDone(recipe.title, done + 1).text;
    notify(copy.brewing.timeUp.text, text, `brew-${done}`);
    toast(text);
  });

  const startTimer = (at: number, seconds: number) => {
    unlockChime();
    if (typeof Notification !== "undefined" && Notification.permission === "default") {
      void Notification.requestPermission();
    }
    start(at, seconds);
  };

  const toggle = () => {
    if (!step?.timerSeconds) return;
    const timer = timers.get(index);
    if (timer && timer.endsAt !== null) pause(index);
    else if (timer?.done) reset(index);
    else startTimer(index, step.timerSeconds);
  };

  const go = (to: number) => {
    // Every tap re-arms audio, which iOS suspends after the screen locks.
    unlockChime();
    const next = Math.min(count - 1, Math.max(0, to));
    if (next !== index) movedAt.current = Date.now();
    setIndex(next);
  };

  useHotkey("ArrowRight", () => go(index + 1));
  useHotkey("ArrowLeft", () => go(index - 1));
  // Space on a focused button or link presses it, as usual; elsewhere it
  // starts or pauses the step's timer.
  useHotkey(
    "Space",
    (event) => {
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest("button, a, [role=button], input, select, textarea")) return;
      if (!step?.timerSeconds) return;
      event.preventDefault();
      toggle();
    },
    { preventDefault: false },
  );

  const brewed = async () => {
    if (Date.now() - movedAt.current < 700) return;
    setBusy(true);
    try {
      settleRecipe(queryClient, await markCooked(recipe.id, localToday()));
      toast(copy.brewing.brewedToast.text);
      await navigate({ to: "/recipes/$id", params: { id: recipe.id } });
    } catch {
      toast(copy.brewing.couldntSave.text, "error");
    } finally {
      setBusy(false);
    }
  };

  const others = [...timers].filter(([at]) => at !== index);

  if (count === 0 || !step) {
    return (
      <div {...stylex.props(styles.screen)}>
        <EmptyState
          message={copy.brewing.noSteps.text}
          actions={
            <ButtonLink to="/recipes/$id/edit" params={{ id: recipe.id }} variant="secondary">
              {copy.brewing.editRecipe.text}
            </ButtonLink>
          }
        />
      </div>
    );
  }

  const ingredients = (matched[index] ?? []).flatMap((i) => recipe.ingredients[i] ?? []);

  return (
    <main {...stylex.props(styles.screen)}>
      <header {...stylex.props(styles.top)}>
        <Link
          to="/recipes/$id"
          params={{ id: recipe.id }}
          {...stylex.props(styles.title, focusRing.ring)}
        >
          <span aria-hidden="true">‹ </span>
          <span {...stylex.props(styles.srOnly)}>{copy.brewing.leave.text}: </span>
          {recipe.title}
        </Link>
        <span {...stylex.props(styles.count)}>{copy.brewing.stepOf(index + 1, count).text}</span>
      </header>
      <div
        role="progressbar"
        aria-valuemin={1}
        aria-valuemax={count}
        aria-valuenow={index + 1}
        aria-valuetext={copy.brewing.stepOf(index + 1, count).text}
        {...stylex.props(styles.bar)}
      >
        <span {...stylex.props(styles.barFill((index + 1) / count))} />
      </div>

      <p aria-live="polite" {...stylex.props(styles.srOnly)}>
        {copy.brewing.stepOf(index + 1, count).text}. {step.text}
      </p>
      <section {...stylex.props(styles.body)}>
        {step.section ? <p {...stylex.props(styles.section)}>{step.section}</p> : null}
        <StepText text={step.text} />

        {ingredients.length > 0 ? (
          <div>
            <h2 {...stylex.props(styles.label)}>{copy.brewing.forThisStep.text}</h2>
            <ul {...stylex.props(styles.ingredients)}>
              {ingredients.map((line, i) => (
                <IngredientLine key={i} line={line} factor={factor} units={units} />
              ))}
            </ul>
          </div>
        ) : null}

        {step.timerSeconds ? (
          <TimerRing
            seconds={step.timerSeconds}
            timer={timers.get(index)}
            now={now}
            onToggle={toggle}
            onReset={() => reset(index)}
          />
        ) : null}
      </section>

      {others.length > 0 ? (
        <div role="group" aria-label={copy.brewing.timers.text} {...stylex.props(styles.others)}>
          {others.map(([at, timer]) => (
            <button
              key={at}
              type="button"
              onClick={() => go(at)}
              {...stylex.props(styles.otherTimer, timer.done && styles.otherDone, focusRing.ring)}
            >
              {copy.brewing.timerFor(at + 1).text} ·{" "}
              <span {...stylex.props(styles.mono)}>
                {timer.done ? copy.brewing.timeUp.text : clock(secondsLeft(timer, now))}
              </span>
            </button>
          ))}
        </div>
      ) : null}

      <footer {...stylex.props(styles.controls)}>
        <div {...stylex.props(styles.buttons)}>
          <Button variant="secondary" onClick={() => go(index - 1)} disabled={index === 0}>
            {copy.brewing.previousStep.text}
          </Button>
          {index < count - 1 ? (
            <Button key="next" onClick={() => go(index + 1)}>
              {copy.brewing.nextStep.text}
            </Button>
          ) : (
            <Button key="brewed" onClick={() => void brewed()} disabled={busy}>
              {copy.brewing.brewed.text}
            </Button>
          )}
        </div>
        <p {...stylex.props(styles.note)}>
          {wake === "unsupported"
            ? copy.brewing.wakeOff.text
            : wake === "off"
              ? copy.brewing.wakeRefused.text
              : copy.brewing.wakeOn.text}
        </p>
        <p {...stylex.props(styles.note, styles.keys)}>{copy.brewing.keys.text}</p>
      </footer>
    </main>
  );
}

function IngredientLine({
  line,
  factor,
  units,
}: {
  line: Ingredient;
  factor: number;
  units: UnitSystemChoice;
}) {
  const measure = line.quantity ? displayMeasure(line.quantity, line.unit, factor, units) : null;
  return (
    <li {...stylex.props(styles.ingredient)}>
      <span {...stylex.props(styles.amount, quantity.value)}>
        {measure ? (
          <>
            {measure.amount}
            {measure.unit ? <span {...stylex.props(quantity.unit)}> {measure.unit}</span> : null}
          </>
        ) : null}
      </span>
      <span>{[line.item, line.note].filter(Boolean).join(", ")}</span>
    </li>
  );
}

const RADIUS = 52;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

function TimerRing({
  seconds,
  timer,
  now,
  onToggle,
  onReset,
}: {
  seconds: number;
  timer: StepTimer | undefined;
  now: number;
  onToggle: () => void;
  onReset: () => void;
}) {
  const left = timer ? secondsLeft(timer, now) : seconds;
  const running = timer?.endsAt != null;
  const done = timer?.done ?? false;
  const label = done
    ? copy.brewing.reset.text
    : running
      ? copy.brewing.pause.text
      : timer
        ? copy.brewing.resume.text
        : copy.brewing.startTimer.text;
  return (
    <div {...stylex.props(styles.timer)}>
      <div {...stylex.props(styles.ring)}>
        <svg viewBox="0 0 120 120" aria-hidden="true" {...stylex.props(styles.ringSvg)}>
          <circle cx="60" cy="60" r={RADIUS} {...stylex.props(styles.track)} />
          <circle
            cx="60"
            cy="60"
            r={RADIUS}
            strokeDasharray={CIRCUMFERENCE}
            strokeDashoffset={CIRCUMFERENCE * (1 - left / seconds)}
            {...stylex.props(styles.progress)}
          />
        </svg>
        <span role="timer" aria-live="off" {...stylex.props(styles.time)}>
          {done ? copy.brewing.timeUp.text : clock(left)}
        </span>
      </div>
      <div {...stylex.props(styles.timerButtons)}>
        <Button variant="secondary" onClick={onToggle}>
          {label}
        </Button>
        {timer && !done ? (
          <Button variant="ghost" onClick={onReset}>
            {copy.brewing.reset.text}
          </Button>
        ) : null}
      </div>
    </div>
  );
}

const phone = "@media (max-width: 767px)";

const styles = stylex.create({
  screen: {
    boxSizing: "border-box",
    minHeight: "100dvh",
    maxWidth: 680,
    marginInline: "auto",
    display: "flex",
    flexDirection: "column",
    gap: 16,
    paddingBlock: { default: 28, [phone]: 18 },
    paddingInline: { default: 28, [phone]: 20 },
    paddingBottom: { default: 28, [phone]: "max(20px, env(safe-area-inset-bottom))" },
  },
  top: { display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12 },
  title: {
    minWidth: 0,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
    color: colors.subtext,
    fontSize: 14,
    textDecoration: "none",
    borderRadius: 4,
  },
  count: { flexShrink: 0, fontFamily: fonts.mono, fontSize: 12.5, color: colors.overlay1 },
  bar: { height: 4, borderRadius: 4, backgroundColor: colors.surface0, overflow: "hidden" },
  barFill: (fraction: number) => ({
    display: "block",
    height: "100%",
    width: `${fraction * 100}%`,
    backgroundColor: colors.magic,
    transitionProperty: "width",
    transitionDuration: "200ms",
  }),
  body: { display: "flex", flexDirection: "column", gap: 20, flexGrow: 1 },
  section: {
    margin: 0,
    fontFamily: fonts.mono,
    fontSize: 11,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.subtext,
  },
  stepText: {
    margin: 0,
    fontSize: { default: 26, [phone]: 21 },
    lineHeight: 1.45,
    fontWeight: 500,
    letterSpacing: "-0.01em",
    color: colors.ink,
    whiteSpace: "pre-wrap",
  },
  inlineMeasure: { fontFamily: fonts.mono, fontSize: "0.85em", color: colors.magic },
  label: {
    margin: 0,
    marginBottom: 6,
    fontFamily: fonts.mono,
    fontSize: 11,
    fontWeight: 500,
    letterSpacing: "0.08em",
    textTransform: "uppercase",
    color: colors.subtext,
  },
  ingredients: { listStyle: "none", margin: 0, padding: 0 },
  ingredient: {
    display: "grid",
    gridTemplateColumns: "minmax(72px, max-content) minmax(0, 1fr)",
    gap: 12,
    alignItems: "baseline",
    paddingBlock: 7,
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: colors.surface0,
    fontSize: 16,
  },
  amount: { textAlign: "end" },
  timer: { display: "flex", flexDirection: "column", alignItems: "center", gap: 12 },
  ring: { position: "relative", width: 160, height: 160, display: "grid", placeItems: "center" },
  ringSvg: { position: "absolute", inset: 0, transform: "rotate(-90deg)" },
  track: { fill: "none", stroke: colors.surface0, strokeWidth: 8 },
  progress: {
    fill: "none",
    stroke: colors.heat,
    strokeWidth: 8,
    strokeLinecap: "round",
    transitionProperty: "stroke-dashoffset",
    transitionDuration: "250ms",
    transitionTimingFunction: "linear",
  },
  time: { fontFamily: fonts.mono, fontSize: 30, fontWeight: 600, color: colors.ink },
  timerButtons: { display: "flex", gap: 8 },
  others: { display: "flex", flexWrap: "wrap", gap: 8 },
  otherTimer: {
    paddingBlock: 6,
    paddingInline: 12,
    minHeight: 36,
    borderRadius: 999,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: `color-mix(in srgb, ${colors.heat} 55%, transparent)`,
    backgroundColor: `color-mix(in srgb, ${colors.heat} 14%, transparent)`,
    color: colors.ink,
    fontFamily: fonts.ui,
    fontSize: 13,
    cursor: "pointer",
  },
  otherDone: { borderColor: colors.heat, fontWeight: 600 },
  mono: { fontFamily: fonts.mono },
  // Stays in reach at the bottom of the screen when a step runs long.
  controls: {
    position: "sticky",
    bottom: 0,
    display: "flex",
    flexDirection: "column",
    gap: 10,
    paddingTop: 10,
    paddingBottom: { default: 0, [phone]: "env(safe-area-inset-bottom)" },
    backgroundColor: colors.base,
  },
  buttons: {
    display: "grid",
    gridTemplateColumns: "1fr 2fr",
    gap: 10,
  },
  note: { margin: 0, textAlign: "center", fontSize: 12, color: colors.overlay1 },
  keys: { display: { default: "block", [phone]: "none" } },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
});
