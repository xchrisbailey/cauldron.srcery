import { BunHttpServer, BunRuntime } from "@effect/platform-bun";
import { Effect, Layer } from "effect";
import { HttpRouter } from "effect/http";
import { AppConfig } from "./AppConfig.ts";
import { Jobs, Routes, Services } from "./App.ts";
import { Observability } from "./Observability.ts";

const ServerLayer = Layer.unwrap(
  Effect.gen(function* () {
    const { port } = yield* AppConfig;
    return Layer.merge(HttpRouter.serve(Routes), Jobs).pipe(
      Layer.provide(BunHttpServer.layer({ port })),
    );
  }),
).pipe(Layer.provide(Services), Layer.provide(Observability), Layer.provide(AppConfig.layer));

Layer.launch(ServerLayer).pipe(BunRuntime.runMain);
