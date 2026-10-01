import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import { Context, Effect, Layer, Schema } from "effect";

// Fetching what a user points us at (a photo URL now, recipe pages in #13)
// from the server. Guards against SSRF: http(s) only, no credentials in the
// URL, every hop's host must resolve to public addresses only, redirects are
// followed by hand and checked the same way, and bodies are size- and
// time-capped.
//
// A name could still resolve differently between the check and the fetch
// (DNS rebinding). Closing that needs pinning the connection to the checked
// address, which Bun's fetch can't do with TLS; revisit with hosting (#21),
// where an egress proxy can enforce it.

export class FetchError extends Schema.TaggedError<FetchError>()("FetchError", {
  reason: Schema.Literals(["blocked", "unreachable", "status", "tooLarge", "timeout"]),
  detail: Schema.optional(Schema.String),
}) {}

export interface Fetched {
  readonly bytes: Uint8Array;
  readonly contentType: string | null;
  readonly url: string;
}

export interface FetchOptions {
  readonly maxBytes: number;
  /** Sent as Accept. */
  readonly accept?: string;
}

const MAX_REDIRECTS = 3;
const TIMEOUT_MS = 10_000;

const v4ToInt = (ip: string) => ip.split(".").reduce((n, part) => n * 256 + Number(part), 0);
const inV4 = (ip: string, base: string, bits: number) => {
  const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
  return (v4ToInt(ip) & mask) >>> 0 === (v4ToInt(base) & mask) >>> 0;
};

const PRIVATE_V4: ReadonlyArray<readonly [string, number]> = [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["198.51.100.0", 24],
  ["203.0.113.0", 24],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
];

/** Whether an address is somewhere a user-supplied URL must never reach. */
export const isPrivateAddress = (ip: string): boolean => {
  if (isIP(ip) === 4) return PRIVATE_V4.some(([base, bits]) => inV4(ip, base, bits));
  const v6 = ip.toLowerCase();
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(v6);
  if (mapped) return isPrivateAddress(mapped[1]!);
  return (
    v6 === "::" ||
    v6 === "::1" ||
    v6.startsWith("fc") ||
    v6.startsWith("fd") ||
    v6.startsWith("fe8") ||
    v6.startsWith("fe9") ||
    v6.startsWith("fea") ||
    v6.startsWith("feb") ||
    v6.startsWith("ff") ||
    v6.startsWith("64:ff9b:") ||
    v6.startsWith("2001:db8:")
  );
};

const blocked = (detail: string) => new FetchError({ reason: "blocked", detail });

/** Checks a URL's scheme, credentials and port, and that its host resolves only to public addresses. */
const checkUrl = Effect.fn("RemoteFetch.checkUrl")(function* (raw: string) {
  const url = yield* Effect.try({ try: () => new URL(raw), catch: () => blocked("not a URL") });
  if (url.protocol !== "http:" && url.protocol !== "https:") return yield* blocked("scheme");
  if (url.username || url.password) return yield* blocked("credentials");
  if (url.port && url.port !== "80" && url.port !== "443") return yield* blocked("port");
  const host = url.hostname.replace(/^\[|\]$/g, "");
  const addresses = isIP(host)
    ? [host]
    : yield* Effect.tryPromise({
        try: async () => (await lookup(host, { all: true, verbatim: true })).map((a) => a.address),
        catch: () => new FetchError({ reason: "unreachable", detail: "dns" }),
      });
  if (addresses.length === 0 || addresses.some(isPrivateAddress)) {
    return yield* blocked("private address");
  }
  return url;
});

const readCapped = (response: Response, maxBytes: number) =>
  Effect.tryPromise({
    try: async () => {
      const declared = Number(response.headers.get("content-length"));
      if (Number.isFinite(declared) && declared > maxBytes)
        throw new FetchError({ reason: "tooLarge" });
      const reader = response.body?.getReader();
      if (!reader) return new Uint8Array();
      const chunks: Array<Uint8Array> = [];
      let size = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > maxBytes) {
          await reader.cancel();
          throw new FetchError({ reason: "tooLarge" });
        }
        chunks.push(value);
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.byteLength;
      }
      return bytes;
    },
    catch: (cause) =>
      cause instanceof FetchError
        ? cause
        : new FetchError({ reason: "unreachable", detail: "read" }),
  });

export class RemoteFetch extends Context.Service<
  RemoteFetch,
  { readonly get: (url: string, options: FetchOptions) => Effect.Effect<Fetched, FetchError> }
>()("cauldron/api/RemoteFetch") {
  static readonly layer = Layer.succeed(
    RemoteFetch,
    RemoteFetch.of({
      get: Effect.fn("RemoteFetch.get")(function* (start, options) {
        let next = start;
        for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
          const url = yield* checkUrl(next);
          const response = yield* Effect.tryPromise({
            try: (signal) =>
              fetch(url, {
                redirect: "manual",
                signal: AbortSignal.any([signal, AbortSignal.timeout(TIMEOUT_MS)]),
                headers: {
                  "user-agent": "Cauldron/1.0 (+https://srcery.computer)",
                  ...(options.accept ? { accept: options.accept } : {}),
                },
              }),
            catch: (cause) =>
              new FetchError({
                reason:
                  cause instanceof DOMException && cause.name === "TimeoutError"
                    ? "timeout"
                    : "unreachable",
              }),
          });
          if (response.status >= 300 && response.status < 400) {
            const location = response.headers.get("location");
            if (!location) return yield* new FetchError({ reason: "status", detail: "redirect" });
            next = new URL(location, url).toString();
            continue;
          }
          if (!response.ok) {
            return yield* new FetchError({ reason: "status", detail: String(response.status) });
          }
          const bytes = yield* readCapped(response, options.maxBytes);
          return { bytes, contentType: response.headers.get("content-type"), url: url.toString() };
        }
        return yield* new FetchError({ reason: "status", detail: "too many redirects" });
      }),
    }),
  );

  /** Serves fixed responses by URL, so importer and photo tests never touch the network. */
  static readonly layerTest = (
    responses: Readonly<
      Record<string, { readonly bytes: Uint8Array; readonly contentType: string }>
    >,
  ) =>
    Layer.succeed(
      RemoteFetch,
      RemoteFetch.of({
        get: Effect.fn("RemoteFetch.get")(function* (url, options) {
          const found = responses[url];
          if (!found) return yield* new FetchError({ reason: "status", detail: "404" });
          if (found.bytes.byteLength > options.maxBytes) {
            return yield* new FetchError({ reason: "tooLarge" });
          }
          return { ...found, url };
        }),
      }),
    );
}

export { checkUrl as checkRemoteUrl };
