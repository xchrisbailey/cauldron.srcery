import { Config, Effect, Layer, Option } from "effect";
import { FetchHttpClient } from "effect/http";
import { OtlpLogger, OtlpSerialization, OtlpTracer } from "effect/observability";
import { AppConfig } from "./AppConfig.ts";

// Exports traces and logs over OTLP/HTTP when OTEL_EXPORTER_OTLP_ENDPOINT is
// set (e.g. http://localhost:4318). Without it, spans stay in process and
// logs go to the console.
export const Observability = Layer.unwrap(
  Effect.gen(function* () {
    const endpoint = yield* Config.option(Config.String("OTEL_EXPORTER_OTLP_ENDPOINT"));
    if (Option.isNone(endpoint)) return Layer.empty;
    const { version } = yield* AppConfig;
    const resource = { serviceName: "cauldron-api", serviceVersion: version };
    const base = endpoint.value.replace(/\/+$/, "");
    return Layer.mergeAll(
      OtlpTracer.layer({ url: `${base}/v1/traces`, resource }),
      OtlpLogger.layer({ url: `${base}/v1/logs`, resource, mergeWithExisting: true }),
    ).pipe(Layer.provide(OtlpSerialization.layerJson), Layer.provide(FetchHttpClient.layer));
  }),
);
