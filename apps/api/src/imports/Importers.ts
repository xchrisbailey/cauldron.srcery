import type { ImportSource } from "@cauldron/shared";
import { Context, Effect, Layer } from "effect";
import type { RemoteFetch } from "../RemoteFetch.ts";
import { fromText } from "./fromText.ts";
import type { RecipeExtractor } from "./RecipeExtractor.ts";
import { failed, type ImportFailed, type Imported } from "./result.ts";
import { fromWeb } from "./web.ts";

// One importer per source type, behind one interface. Each tries its
// extractors in order, cheapest first, and fails with a typed reason the
// job turns into plain copy.

export { fromText } from "./fromText.ts";
export { ImportFailed, type Imported } from "./result.ts";

export interface ImportRequest {
  readonly source: ImportSource;
  readonly url: string | null;
  readonly text: string | null;
}

export class Importers extends Context.Service<
  Importers,
  { readonly run: (request: ImportRequest) => Effect.Effect<Imported, ImportFailed> }
>()("cauldron/api/Importers") {
  static readonly layer = Layer.effect(
    Importers,
    Effect.gen(function* () {
      const context = yield* Effect.context<RecipeExtractor | RemoteFetch>();
      return Importers.of({
        run: Effect.fn("Importers.run")(function* (request) {
          if (request.text !== null) {
            const read = yield* fromText(request.text, "text");
            return { ...read, raw: null, sourceUrl: null };
          }
          if (request.url === null) return yield* failed("couldntRead");
          // Instagram and TikTok are read by the social importer (#16).
          if (request.source !== "web") return yield* failed("couldntRead");
          return yield* fromWeb(request.url);
        }, Effect.provideContext(context)),
      });
    }),
  );
}
