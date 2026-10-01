import type { UnitSystemChoice } from "@cauldron/shared";
import { usePreference } from "./preference";

// How quantities are shown (as written, metric or US): a per-viewer
// preference remembered in this browser, shared by the recipe page and cook mode.

const decodeUnits = (raw: string | null): UnitSystemChoice =>
  raw === "metric" || raw === "us" ? raw : "asWritten";

export function useUnitChoice() {
  const [units, choose] = usePreference("cauldron:units", decodeUnits, "asWritten");
  return [units, choose] as const;
}
