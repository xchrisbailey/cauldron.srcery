import type { UnitSystemChoice } from "@cauldron/shared";
import { useEffect, useState } from "react";

// How quantities are shown (as written, metric or US): a per-viewer
// preference remembered in this browser, shared by the recipe page and cook mode.

const UNIT_KEY = "cauldron:units";

export const savedUnits = (): UnitSystemChoice => {
  try {
    const saved = window.localStorage.getItem(UNIT_KEY);
    return saved === "metric" || saved === "us" ? saved : "asWritten";
  } catch {
    // Storage is optional.
    return "asWritten";
  }
};

export function useUnitChoice() {
  const [units, setUnits] = useState<UnitSystemChoice>("asWritten");
  useEffect(() => setUnits(savedUnits()), []);
  const choose = (next: UnitSystemChoice) => {
    setUnits(next);
    try {
      window.localStorage.setItem(UNIT_KEY, next);
    } catch {
      // Storage is optional.
    }
  };
  return [units, choose] as const;
}
