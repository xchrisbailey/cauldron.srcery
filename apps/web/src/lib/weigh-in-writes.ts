import { copy, type DiaryDay, type LocalDate } from "@cauldron/shared";
import { useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";
import { useToast } from "../components/ui";
import { messageOr } from "./api-failure";
import { shortDate } from "./dates";
import { trackerApi, trackerKeys } from "./tracker";

// Weigh-in writes. The day in the cache changes at once (the diary header shows
// the new weight straight away), then settles with what the API says and rolls
// back if it refuses. The weigh-in lists and trend refetch afterwards.

export function useWeighInWrites() {
  const cache = useQueryClient();
  const notify = useToast();

  return useMemo(() => {
    const run = async (
      date: string,
      weighIn: DiaryDay["weighIn"],
      call: () => Promise<unknown>,
      failure: string,
    ) => {
      await cache.cancelQueries({ queryKey: trackerKeys.day(date) });
      const saved = cache.getQueryData<DiaryDay>(trackerKeys.day(date));
      cache.setQueryData<DiaryDay>(trackerKeys.day(date), (day) =>
        day ? { ...day, weighIn } : day,
      );
      try {
        await call();
        return true;
      } catch (error) {
        cache.setQueryData(trackerKeys.day(date), saved);
        notify(messageOr(error, failure), "error");
        return false;
      } finally {
        void cache.invalidateQueries({ queryKey: trackerKeys.day(date) });
        void cache.invalidateQueries({ queryKey: trackerKeys.weighIns });
      }
    };

    /** Logs the weight for a day, replacing any weigh-in already there. */
    const save = (date: string, weightKg: number) =>
      run(
        date,
        { date: date as LocalDate, weightKg },
        () => trackerApi.weighIn(date as LocalDate, weightKg),
        copy.tracker.weight.couldntSave.text,
      );

    /** Removes a day's weigh-in, with an undo that puts it back. */
    const remove = async (date: string, weightKg: number) => {
      const ok = await run(
        date,
        null,
        () => trackerApi.removeWeighIn(date as LocalDate),
        copy.tracker.weight.couldntRemove.text,
      );
      if (ok)
        notify(copy.tracker.weight.removed(shortDate(date, true)).text, "info", {
          label: copy.tracker.diary.undo.text,
          onClick: () => void save(date, weightKg),
        });
      return ok;
    };

    return { save, remove };
  }, [cache, notify]);
}
