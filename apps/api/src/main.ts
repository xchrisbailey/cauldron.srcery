import { BunHttpServer, BunRuntime } from "@effect/platform-bun";
import { Effect, Layer } from "effect";
import { HttpRouter } from "effect/http";
import { AppConfig } from "./AppConfig.ts";
import { Routes } from "./App.ts";

const ServerLayer = Layer.unwrap(
  Effect.gen(function* () {
    const { port } = yield* AppConfig;
    return HttpRouter.serve(Routes).pipe(Layer.provide(BunHttpServer.layer({ port })));
  }),
).pipe(Layer.provide(AppConfig.layer));

Layer.launch(ServerLayer).pipe(BunRuntime.runMain);
