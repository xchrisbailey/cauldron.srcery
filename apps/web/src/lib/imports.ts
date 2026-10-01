import type { ImportId, ImportInput, ImportJob, RecipeInput } from "@cauldron/shared";
import { queryOptions } from "@tanstack/react-query";
import { callApi } from "./api";

// Distill jobs for TanStack Query. A job is polled while it runs, then left
// alone: a finished job doesn't change until it's saved.

export const importKeys = {
  detail: (id: string) => ["imports", id] as const,
};

const pending = (job: ImportJob | undefined) =>
  job === undefined || job.status === "queued" || job.status === "running";

export const importQuery = (id: string) =>
  queryOptions({
    queryKey: importKeys.detail(id),
    queryFn: () => callApi((c) => c.imports.get({ params: { id: id as ImportId } })),
    refetchInterval: (query) => (pending(query.state.data) ? 1000 : false),
    // The draft is reviewed once; refetching it on focus would only reset the view.
    refetchOnWindowFocus: (query) => pending(query.state.data),
  });

export const startImport = (input: ImportInput) =>
  callApi((c) => c.imports.start({ payload: input }));

export const cancelImport = (id: string) =>
  callApi((c) => c.imports.cancel({ params: { id: id as ImportId } }));

export const saveImport = (id: string, input: RecipeInput) =>
  callApi((c) => c.imports.save({ params: { id: id as ImportId }, payload: input }));
