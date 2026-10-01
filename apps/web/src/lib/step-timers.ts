import { useCallback, useEffect, useRef, useState } from "react";

// Step timers for cook mode. Each step's timer runs on its own, so moving to
// another step doesn't stop it. Time is kept as an end time, not a counter,
// so a backgrounded tab that skips ticks still finishes on time.

export interface StepTimer {
  /** Seconds the timer was set for. */
  readonly total: number;
  /** Seconds left when paused; ignored while running. */
  readonly left: number;
  /** When it will finish (ms since the epoch), while running. */
  readonly endsAt: number | null;
  readonly done: boolean;
}

/** Seconds left on a timer at `now`. */
export const secondsLeft = (timer: StepTimer, now: number) =>
  timer.endsAt === null ? timer.left : Math.max(0, (timer.endsAt - now) / 1000);

/** 7:02, or 1:05:00 for an hour or more. */
export const clock = (seconds: number) => {
  const s = Math.ceil(seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const rest = String(s % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${rest}` : `${m}:${rest}`;
};

export function useStepTimers(onDone: (step: number) => void) {
  const [timers, setTimers] = useState<ReadonlyMap<number, StepTimer>>(new Map());
  const [now, setNow] = useState(() => Date.now());
  const done = useRef(onDone);
  useEffect(() => {
    done.current = onDone;
  });

  // The latest timers, for the ticker to check without a side effect inside a
  // state updater (which React may run twice).
  const latest = useRef(timers);
  useEffect(() => {
    latest.current = timers;
  });

  const running = [...timers.values()].some((t) => t.endsAt !== null && !t.done);
  useEffect(() => {
    if (!running) return;
    const tick = () => {
      const at = Date.now();
      setNow(at);
      const due = [...latest.current].filter(
        ([, t]) => t.endsAt !== null && !t.done && t.endsAt <= at,
      );
      if (due.length === 0) return;
      const next = new Map(latest.current);
      for (const [step, timer] of due) {
        next.set(step, { ...timer, left: 0, endsAt: null, done: true });
      }
      latest.current = next;
      setTimers(next);
      for (const [step] of due) done.current(step);
    };
    const id = window.setInterval(tick, 250);
    return () => window.clearInterval(id);
  }, [running]);

  const update = (step: number, f: (timer: StepTimer | undefined) => StepTimer | undefined) =>
    setTimers((current) => {
      const next = new Map(current);
      const value = f(current.get(step));
      if (value === undefined) next.delete(step);
      else next.set(step, value);
      return next;
    });

  const start = useCallback((step: number, total: number) => {
    const at = Date.now();
    setNow(at);
    update(step, (t) => {
      const left = t && !t.done ? t.left : total;
      return { total, left, endsAt: at + left * 1000, done: false };
    });
  }, []);

  const pause = useCallback((step: number) => {
    const at = Date.now();
    update(step, (t) =>
      t && t.endsAt !== null ? { ...t, left: secondsLeft(t, at), endsAt: null } : t,
    );
  }, []);

  const reset = useCallback((step: number) => update(step, () => undefined), []);

  return { timers, now, start, pause, reset };
}

let audio: AudioContext | null = null;

/** Call from every tap (a user gesture), so the chime is allowed to play later. */
export const unlockChime = () => {
  try {
    audio ??= new AudioContext();
    if (audio.state === "suspended") void audio.resume();
  } catch {
    // No Web Audio: the notification and the screen still say it's done.
  }
};

/** Three short tones. */
export const chime = () => {
  if (!audio) return;
  // iOS suspends audio after the screen locks or a call; wake it first.
  if (audio.state !== "running") void audio.resume();
  const start = audio.currentTime;
  for (let i = 0; i < 3; i++) {
    const tone = audio.createOscillator();
    const gain = audio.createGain();
    tone.frequency.value = 880;
    gain.gain.setValueAtTime(0.0001, start + i * 0.35);
    gain.gain.exponentialRampToValueAtTime(0.3, start + i * 0.35 + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + i * 0.35 + 0.25);
    tone.connect(gain).connect(audio.destination);
    tone.start(start + i * 0.35);
    tone.stop(start + i * 0.35 + 0.3);
  }
};
