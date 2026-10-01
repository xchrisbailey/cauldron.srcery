import { useEffect, useState } from "react";

/**
 * Keeps the screen on while the calling component is mounted (Screen Wake
 * Lock). The browser drops the lock when the page is hidden, so it's taken
 * again whenever the page comes back. Returns whether the browser supports it
 * (null until known).
 */
export function useWakeLock(): boolean | null {
  const [supported, setSupported] = useState<boolean | null>(null);
  useEffect(() => {
    if (!("wakeLock" in navigator)) {
      setSupported(false);
      return;
    }
    setSupported(true);
    let lock: WakeLockSentinel | null = null;
    let active = true;
    const acquire = async () => {
      try {
        const next = await navigator.wakeLock.request("screen");
        if (active) lock = next;
        else void next.release();
      } catch {
        // Refused, for example on low battery. The note still says what to expect.
      }
    };
    const onVisible = () => {
      if (document.visibilityState === "visible" && (lock === null || lock.released)) {
        void acquire();
      }
    };
    void acquire();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      active = false;
      document.removeEventListener("visibilitychange", onVisible);
      void lock?.release();
    };
  }, []);
  return supported;
}
