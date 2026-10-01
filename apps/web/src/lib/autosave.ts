import { Debouncer } from "@tanstack/react-pacer";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";

// Autosave for a form: each change is debounced with Pacer, then saved. Saves
// run one at a time, in order, so an older save never lands last, and a form
// put back to what's saved sends nothing. Framework-free so it can be tested
// with fake timers; `useAutosave` binds it to a component.

export type SaveStatus = "idle" | "pending" | "saving" | "saved" | "kept" | "invalid" | "error";

export interface AutosaveOptions<T> {
  /** Saves the values; resolves to the status to show. "saved" and "kept" count as persisted. */
  persist: (values: T) => Promise<SaveStatus>;
  /** What the values say, as a string, so equal forms compare equal. */
  key: (values: T) => string;
  /** The values already persisted, so an unchanged form isn't saved again. */
  initial: T;
  /** Milliseconds of quiet before a change is saved. */
  wait: number;
}

export interface Autosave<T> {
  /** Hand over the form's current values. */
  change: (values: T) => void;
  /** Save a waiting change now rather than after the wait. */
  flush: () => void;
  /** Drop the waiting change and any queued save, so nothing more is written. */
  cancel: () => void;
  /** Resolves once the saves queued so far have finished. */
  idle: () => Promise<void>;
  /** Whether the latest values differ from what's persisted. */
  dirty: () => boolean;
  /** The status to show. */
  status: () => SaveStatus;
  /** Hear about status changes; returns the unsubscribe. */
  subscribe: (listener: () => void) => () => void;
}

export const createAutosave = <T>({
  persist,
  key,
  initial,
  wait,
}: AutosaveOptions<T>): Autosave<T> => {
  const listeners = new Set<() => void>();
  let status: SaveStatus = "idle";
  /** The status of the last save that finished, shown again when the form matches it. */
  let settled: SaveStatus = "idle";
  let saved = key(initial);
  let latest = { values: initial, key: saved };
  let queue: Promise<void> = Promise.resolve();
  /** Bumped by `cancel`, so saves queued before it don't run. */
  let generation = 0;

  const set = (next: SaveStatus) => {
    if (next === status) return;
    status = next;
    for (const listener of listeners) listener();
  };

  // If the form changed while a save was running, the newest values go next.
  const save = (next: T) => {
    const at = generation;
    const run = queue.then(async () => {
      if (at !== generation) return;
      const shot = key(next);
      if (shot !== saved) {
        set("saving");
        const result = await persist(next);
        if (at !== generation) return;
        if (result === "saved" || result === "kept") saved = shot;
        settled = result;
      }
      if (latest.key === saved) set(settled);
      else if (latest.key !== shot) debouncer.maybeExecute(latest.values);
      else set(settled);
    });
    queue = run.catch(() => undefined);
    return run;
  };

  const debouncer = new Debouncer(save, { wait });

  return {
    change: (values) => {
      const shot = key(values);
      const same = shot === latest.key;
      latest = { values, key: shot };
      if (same) return;
      if (shot === saved) {
        // Back to what's saved (an edit undone): nothing to send.
        debouncer.cancel();
        set(settled);
        return;
      }
      set("pending");
      debouncer.maybeExecute(values);
    },
    flush: () => debouncer.flush(),
    cancel: () => {
      generation++;
      debouncer.cancel();
    },
    idle: () => queue,
    dirty: () => latest.key !== saved,
    status: () => status,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
};

/**
 * Autosave for a component's lifetime. Unmounting, closing or reloading the
 * tab flushes rather than cancels, so the last change is kept.
 */
export const useAutosave = <T>(options: AutosaveOptions<T>) => {
  // The latest persist is the one called, whenever the save runs.
  const persist = useRef(options.persist);
  persist.current = options.persist;
  const [autosave] = useState(() =>
    createAutosave({ ...options, persist: (values) => persist.current(values) }),
  );
  const status = useSyncExternalStore(autosave.subscribe, autosave.status, autosave.status);

  useEffect(() => {
    window.addEventListener("pagehide", autosave.flush);
    return () => {
      window.removeEventListener("pagehide", autosave.flush);
      autosave.flush();
    };
  }, [autosave]);

  return { autosave, status };
};
