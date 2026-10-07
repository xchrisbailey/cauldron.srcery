import { Config, Effect, Layer, Option, Redacted } from "effect";
import { FetchHttpClient } from "effect/http";
import { OtlpLogger, OtlpSerialization, OtlpTracer } from "effect/observability";
import { AppConfig } from "./AppConfig.ts";

/**
 * `OTEL_EXPORTER_OTLP_HEADERS` in its standard form, `name=value,name=value`
 * with percent-encoded values. Entries without a name or an `=` are dropped.
 */
export const parseOtlpHeaders = (raw: string): Record<string, string> =>
  Object.fromEntries(
    raw.split(",").flatMap((pair) => {
      const at = pair.indexOf("=");
      const name = at > 0 ? pair.slice(0, at).trim() : "";
      if (name === "") return [];
      const value = pair.slice(at + 1).trim();
      try {
        return [[name, decodeURIComponent(value)]];
      } catch {
        return [[name, value]];
      }
    }),
  );

// Exports traces and logs over OTLP/HTTP when OTEL_EXPORTER_OTLP_ENDPOINT is
// set (e.g. http://localhost:4318). Without it, spans stay in process and
// logs go to the console. The logs carry user ids and client addresses, so a
// collector on another machine needs https and, through
// OTEL_EXPORTER_OTLP_HEADERS, whatever credential it asks for.
export const Observability = Layer.unwrap(
  Effect.gen(function* () {
    const endpoint = yield* Config.option(Config.String("OTEL_EXPORTER_OTLP_ENDPOINT"));
    if (Option.isNone(endpoint)) return Layer.empty;
    const { version } = yield* AppConfig;
    const resource = { serviceName: "cauldron-api", serviceVersion: version };
    const base = endpoint.value.replace(/\/+$/, "");
    const secret = yield* Config.option(Config.Redacted("OTEL_EXPORTER_OTLP_HEADERS"));
    const headers = Option.match(secret, {
      onNone: () => undefined,
      onSome: (value) => parseOtlpHeaders(Redacted.value(value)),
    });
    return Layer.mergeAll(
      OtlpTracer.layer({ url: `${base}/v1/traces`, resource, headers }),
      OtlpLogger.layer({ url: `${base}/v1/logs`, resource, headers, mergeWithExisting: true }),
    ).pipe(Layer.provide(OtlpSerialization.layerJson), Layer.provide(FetchHttpClient.layer));
  }),
);
