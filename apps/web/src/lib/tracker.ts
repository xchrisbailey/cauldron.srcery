import type {
  BodyProfile,
  DiaryCopyInput,
  DiaryEntryId,
  DiaryEntryInput,
  DiaryEntryUpdate,
  FavouriteId,
  LocalDate,
  TargetsInput,
} from "@cauldron/shared";
import { queryOptions } from "@tanstack/react-query";
import { callApi } from "./api";

// The tracker (#23) for TanStack Query: one day of the diary, the settings
// (body profile and targets), weigh-ins and intake over a range.

export const trackerKeys = {
  all: ["tracker"] as const,
  days: ["tracker", "day"] as const,
  day: (date: string) => ["tracker", "day", date] as const,
  settings: ["tracker", "settings"] as const,
  weighIns: ["tracker", "weigh-ins"] as const,
  weighInRange: (from: string, to: string) => ["tracker", "weigh-ins", from, to] as const,
  intake: ["tracker", "intake"] as const,
  quick: ["tracker", "quick"] as const,
  intakeRange: (from: string, to: string) => ["tracker", "intake", from, to] as const,
};

export const dayQuery = (date: string) =>
  queryOptions({
    queryKey: trackerKeys.day(date),
    queryFn: () => callApi((c) => c.tracker.day({ query: { date } })),
  });

export const settingsQuery = () =>
  queryOptions({
    queryKey: trackerKeys.settings,
    queryFn: () => callApi((c) => c.tracker.settings()),
  });

export const weighInsQuery = (from: string, to: string) =>
  queryOptions({
    queryKey: trackerKeys.weighInRange(from, to),
    queryFn: () => callApi((c) => c.tracker.weighIns({ query: { from, to } })),
  });

export const intakeQuery = (from: string, to: string) =>
  queryOptions({
    queryKey: trackerKeys.intakeRange(from, to),
    queryFn: () => callApi((c) => c.tracker.intake({ query: { from, to } })),
  });

/** Favourites and recents, for one-tap logging. */
export const quickFoodsQuery = () =>
  queryOptions({
    queryKey: trackerKeys.quick,
    queryFn: () => callApi((c) => c.tracker.quickFoods()),
  });

/** The tracker endpoints that write. */
export const trackerApi = {
  add: (input: DiaryEntryInput) => callApi((c) => c.tracker.add({ payload: input })),
  addMany: (entries: ReadonlyArray<DiaryEntryInput>) =>
    callApi((c) => c.tracker.addMany({ payload: { entries } })),
  update: (id: DiaryEntryId, update: DiaryEntryUpdate) =>
    callApi((c) => c.tracker.update({ params: { id }, payload: update })),
  remove: (id: DiaryEntryId) => callApi((c) => c.tracker.remove({ params: { id } })),
  copy: (input: DiaryCopyInput) => callApi((c) => c.tracker.copy({ payload: input })),
  favourite: (entryId: DiaryEntryId) =>
    callApi((c) => c.tracker.favourite({ payload: { entryId } })),
  unfavourite: (id: FavouriteId) => callApi((c) => c.tracker.unfavourite({ params: { id } })),
  saveProfile: (profile: BodyProfile) =>
    callApi((c) => c.tracker.saveProfile({ payload: profile })),
  saveTargets: (targets: TargetsInput) =>
    callApi((c) => c.tracker.saveTargets({ payload: targets })),
  weighIn: (date: LocalDate, weightKg: number) =>
    callApi((c) => c.tracker.weighIn({ params: { date }, payload: { weightKg } })),
  removeWeighIn: (date: LocalDate) => callApi((c) => c.tracker.removeWeighIn({ params: { date } })),
};
