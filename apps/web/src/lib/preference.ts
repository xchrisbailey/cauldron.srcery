import { useEffect, useState } from "react";

/**
 * A per-viewer preference remembered in this browser's localStorage. It starts
 * as `fallback` (so server and first client render agree), then takes the saved
 * value once mounted; `loaded` says when that has happened. `decode` gets the
 * stored text (null when absent or storage is unavailable) and must return a
 * valid value; `encode` turns a value back into text.
 */
export function usePreference<T>(
  key: string,
  decode: (raw: string | null) => T,
  fallback: T,
  encode: (value: T) => string = String,
) {
  const [value, setValue] = useState<T>(fallback);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    let raw: string | null = null;
    try {
      raw = window.localStorage.getItem(key);
    } catch {
      // Storage is optional.
    }
    setValue(decode(raw));
    setLoaded(true);
    // The decoder is fixed per call site.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  const choose = (next: T) => {
    setValue(next);
    try {
      window.localStorage.setItem(key, encode(next));
    } catch {
      // Storage is optional.
    }
  };
  return [value, choose, loaded] as const;
}
