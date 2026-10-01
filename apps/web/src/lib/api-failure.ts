// Classifying what callApi rejects with. callApi keeps the typed error (a
// domain error from @cauldron/shared, a transport error, or a defect), and
// this is the one place that reads its `_tag`. Callers ask `failureOf` instead.

export type FailureTag =
  | "NotFound"
  | "InvalidRequest"
  | "Conflict"
  | "TooManyRequests"
  | "Unavailable"
  | "Unauthorized"
  | "Network"
  | "Defect";

export interface Failure {
  readonly tag: FailureTag;
  /** The error's own message: plain copy for API errors, diagnostic text otherwise. */
  readonly message: string;
}

const API_TAGS: ReadonlyArray<FailureTag> = [
  "NotFound",
  "InvalidRequest",
  "Conflict",
  "TooManyRequests",
  "Unavailable",
  "Unauthorized",
];

// The API's own messages are plain copy, safe to show as they are.
const SHOWABLE: ReadonlyArray<FailureTag> = ["InvalidRequest", "TooManyRequests", "Unavailable"];

const field = (error: unknown, key: string): unknown =>
  typeof error === "object" && error !== null && key in error
    ? (error as Record<string, unknown>)[key]
    : undefined;

export const failureOf = (error: unknown): Failure => {
  const raw = field(error, "message");
  const message = typeof raw === "string" ? raw : "";
  const tag = field(error, "_tag");
  const known = API_TAGS.find((t) => t === tag);
  if (known) return { tag: known, message };
  // fetch rejects with a TypeError when there is no connection; the Effect
  // client wraps that in an HttpClientError.
  if (error instanceof TypeError || tag === "HttpClientError") return { tag: "Network", message };
  return { tag: "Defect", message };
};

/** The API refused the request itself, so retrying it won't help. */
export const refused = (error: unknown) => {
  const { tag } = failureOf(error);
  return tag === "NotFound" || tag === "InvalidRequest";
};

/** A TanStack Query `retry` function: up to `max` retries, none once the API has refused. */
export const retryWhile =
  (max: number) =>
  (count: number, error: unknown): boolean =>
    count < max && !refused(error);

/** The API's plain message when it sent one worth showing, otherwise `fallback`. */
export const messageOr = (error: unknown, fallback: string): string => {
  const { tag, message } = failureOf(error);
  return SHOWABLE.includes(tag) && message !== "" ? message : fallback;
};
