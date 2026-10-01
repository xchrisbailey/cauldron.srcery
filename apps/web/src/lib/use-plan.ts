import type { WeekStartDay } from "@cauldron/shared";
import { useIsMutating, useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";
import { useToast } from "../components/ui";
import { planApi } from "./plan";
import { copyMutationKey, makePlanWrites } from "./plan-writes";

/**
 * The plan writes (plan-writes.ts) over this app's QueryClient, the API and
 * the toast, plus whether a copy of last week is still running.
 */
export function usePlanWrites(startsOn: WeekStartDay) {
  const cache = useQueryClient();
  const notify = useToast();
  const writes = useMemo(
    () => makePlanWrites({ cache, api: planApi, startsOn, notify }),
    [cache, startsOn, notify],
  );
  const copying = useIsMutating({ mutationKey: copyMutationKey }) > 0;
  return { ...writes, copying };
}
