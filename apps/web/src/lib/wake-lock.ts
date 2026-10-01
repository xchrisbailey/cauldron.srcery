import { useEffect, useState } from "react";

export type WakeState = "pending" | "on" | "off" | "unsupported";

/**
 * Keeps the screen on while the calling component is mounted (Screen Wake
 * Lock). The browser drops the lock when the page is hidden, so it's taken
 * again whenever the page comes back. Reports whether the screen is actually
 * being kept on: "off" when the browser refused (for example on low battery).
 */
export function useWakeLock(): WakeState {
  const [state, setState] = useState<WakeState>("pending");
  useEffect(() => {
    if (!("wakeLock" in navigator)) {
      setState("unsupported");
      return;
    }
    let lock: WakeLockSentinel | null = null;
    let requesting = false;
    let active = true;
    const acquire = async () => {
      if (requesting || (lock !== null && !lock.released)) return;
      requesting = true;
      try {
        const next = await navigator.wakeLock.request("screen");
        if (!active) {
          void next.release();
          return;
        }
        lock = next;
        setState("on");
        next.addEventListener("release", () => active && setState("off"));
      } catch {
        if (active) setState("off");
      } finally {
        requesting = false;
      }
    };
    const onVisible = () => {
      if (document.visibilityState === "visible") void acquire();
    };
    void acquire();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      active = false;
      document.removeEventListener("visibilitychange", onVisible);
      void lock?.release();
    };
  }, []);
  return state;
}
