import { DraftField } from "@cauldron/shared";
import { chat, type ChatMiddleware } from "@tanstack/ai";
import { createAnthropicChat } from "@tanstack/ai-anthropic";
import { createGeminiChat } from "@tanstack/ai-gemini";
import { createOpenaiChat } from "@tanstack/ai-openai";
import { Config, Context, Effect, Layer, Option, Redacted, Schema } from "effect";
import { emptyExtracted, type ExtractedRecipe, type Usage } from "./Extracted.ts";

// Model extraction through TanStack AI (#13). One function takes raw text (a
// page's readable text, a caption, a paste) and returns the recipe as
// validated structured output. The provider is a TanStack AI adapter chosen
// by config, so it can change without touching any importer. Ingredient lines
// come back as written; the shared line parser reads them later, the same way
// it reads every other source.

/** What the text is, which tunes the prompt. */
export type ExtractKind = "page" | "caption" | "text";

export interface ExtractInput {
  readonly text: string;
  readonly kind: ExtractKind;
}

/** `found`, or why not: no recipe at all, or one that's only in the video (#17). */
export type ExtractOutcome = "found" | "missing" | "inVideo";

export interface Extraction {
  readonly outcome: ExtractOutcome;
  readonly recipe: ExtractedRecipe;
  readonly usage: Usage | null;
}

export class ExtractError extends Schema.TaggedError<ExtractError>()("ExtractError", {
  reason: Schema.Literals(["unavailable", "failed", "timeout"]),
  detail: Schema.optional(Schema.String),
}) {}

/** Pages are cut to this before they reach the model: far more than any recipe needs. */
export const MODEL_INPUT_MAX = 40_000;
const TIMEOUT = "90 seconds";

const Line = Schema.Struct({
  line: Schema.String.annotate({
    description: "The ingredient line exactly as written, quantity and unit included.",
  }),
  section: Schema.NullOr(Schema.String).annotate({
    description: 'The heading it sits under, like "For the sauce", or null.',
  }),
  unsure: Schema.Boolean.annotate({
    description: "True when you had to guess at this line or it may be misread.",
  }),
});

const Step = Schema.Struct({
  text: Schema.String.annotate({ description: "One step of the method, as written." }),
  section: Schema.NullOr(Schema.String),
  unsure: Schema.Boolean,
});

const Minutes = Schema.NullOr(Schema.Finite).annotate({ description: "Whole minutes, or null." });

/** What the model is asked for. Every key is required and nullable, so it fits strict modes. */
export const ModelRecipe = Schema.Struct({
  recipe: Schema.Literals(["found", "missing", "inVideo"]).annotate({
    description:
      '"found" when the text has a recipe (ingredients and method). "inVideo" when it only points to a recipe shown or spoken in a video. "missing" otherwise.',
  }),
  title: Schema.NullOr(Schema.String),
  description: Schema.NullOr(Schema.String).annotate({
    description: "One or two sentences about the dish from the text, or null. Never invent one.",
  }),
  servings: Schema.NullOr(Schema.Finite),
  prepMinutes: Minutes,
  cookMinutes: Minutes,
  totalMinutes: Minutes,
  ingredients: Schema.Array(Line),
  steps: Schema.Array(Step),
  tags: Schema.Array(Schema.String).annotate({
    description: "Up to five short tags already implied by the text, like a cuisine or a diet.",
  }),
  notes: Schema.NullOr(Schema.String).annotate({
    description: "Tips, storage or substitutions from the text, or null.",
  }),
  unsure: Schema.Array(DraftField).annotate({
    description: "Top-level fields you guessed or aren't sure of.",
  }),
});
export type ModelRecipe = typeof ModelRecipe.Type;

const outputSchema = Schema.toStandardJSONSchemaV1(ModelRecipe)["~standard"].jsonSchema.input({
  target: "draft-2020-12",
});

const RULES = `You read recipes out of messy text and return them as structured data.
- Copy ingredient lines and method steps as written. Don't convert units, rescale or rewrite them.
- Keep one ingredient per line. Keep section headings ("For the sauce") as the section of the lines under them, not as lines.
- Split the method into its steps. Drop step numbers and bullets.
- Leave out anything that isn't the recipe: life stories, ads, comments, hashtags, calls to follow or subscribe.
- Never invent ingredients, steps, amounts or times. Use null when the text doesn't say.
- Mark anything you had to guess as unsure.`;

const KIND_RULES: Record<ExtractKind, string> = {
  page: "The text is the readable content of a web page. Navigation, ads and comments may be mixed in.",
  caption: `The text is a social media caption. Captions mix a story, emojis, hashtags and sometimes the recipe.
- Hashtags and emojis are never ingredients or tags.
- If the caption only says the recipe is in the video, in the comments or behind a link, answer "inVideo".`,
  text: "The text was pasted by the cook. It may be copied from a notes app, an email or a message.",
};

export const promptFor = (input: ExtractInput) => ({
  system: `${RULES}\n${KIND_RULES[input.kind]}`,
  user: input.text.slice(0, MODEL_INPUT_MAX),
});

const decodeModelRecipe = Schema.decodeUnknownEffect(ModelRecipe);

const whole = (value: number | null) =>
  value === null || !Number.isFinite(value) || value < 0 ? null : Math.round(value);

/** The model's answer in the shape every extractor shares. */
export const fromModel = (model: ModelRecipe): ExtractedRecipe => ({
  ...emptyExtracted,
  title: model.title,
  description: model.description,
  servings: whole(model.servings),
  prepMinutes: whole(model.prepMinutes),
  cookMinutes: whole(model.cookMinutes),
  totalMinutes: whole(model.totalMinutes),
  tags: model.tags,
  notes: model.notes,
  ingredients: model.ingredients,
  steps: model.steps,
  unsure: model.unsure,
});

export type ProviderName = "gemini" | "anthropic" | "openai";

export interface Provider {
  readonly name: ProviderName;
  readonly model: string;
  readonly apiKey: Redacted.Redacted<string>;
}

/** Each provider's key and default model, in the order a key picks one when AI_PROVIDER is unset. */
const PROVIDERS: Record<ProviderName, { readonly key: string; readonly model: string }> = {
  gemini: { key: "GEMINI_API_KEY", model: "gemini-3.5-flash-lite" },
  anthropic: { key: "ANTHROPIC_API_KEY", model: "claude-sonnet-5" },
  openai: { key: "OPENAI_API_KEY", model: "gpt-5.5" },
};

const adapterFor = (provider: Provider) => {
  const apiKey = Redacted.value(provider.apiKey);
  switch (provider.name) {
    case "gemini":
      return createGeminiChat(provider.model as Parameters<typeof createGeminiChat>[0], apiKey);
    case "anthropic":
      return createAnthropicChat(
        provider.model as Parameters<typeof createAnthropicChat>[0],
        apiKey,
      );
    case "openai":
      return createOpenaiChat(provider.model as Parameters<typeof createOpenaiChat>[0], apiKey);
  }
};

export class RecipeExtractor extends Context.Service<
  RecipeExtractor,
  {
    /** False when no model is configured; importers then rely on the extractors that need none. */
    readonly available: boolean;
    readonly extract: (input: ExtractInput) => Effect.Effect<Extraction, ExtractError>;
  }
>()("cauldron/api/RecipeExtractor") {
  static readonly layerModel = (provider: Provider) =>
    Layer.succeed(
      RecipeExtractor,
      RecipeExtractor.of({
        available: true,
        extract: Effect.fn("RecipeExtractor.extract")(
          function* (input) {
            const prompt = promptFor(input);
            let inputTokens = 0;
            let outputTokens = 0;
            const usage: ChatMiddleware = {
              name: "cost-log",
              onUsage: (_ctx, info) => {
                inputTokens += info.promptTokens;
                outputTokens += info.completionTokens;
              },
            };
            const raw = yield* Effect.tryPromise({
              try: (signal) => {
                const abortController = new AbortController();
                signal.addEventListener("abort", () => abortController.abort(), { once: true });
                return chat({
                  adapter: adapterFor(provider),
                  systemPrompts: [prompt.system],
                  messages: [{ role: "user", content: prompt.user }],
                  outputSchema,
                  middleware: [usage],
                  abortController,
                });
              },
              catch: (cause) =>
                new ExtractError({
                  reason: "failed",
                  detail: cause instanceof Error ? cause.message : "model call failed",
                }),
            });
            const model = yield* decodeModelRecipe(raw).pipe(
              Effect.mapError(() => new ExtractError({ reason: "failed", detail: "bad output" })),
            );
            return {
              outcome: model.recipe,
              recipe: fromModel(model),
              usage: { model: provider.model, inputTokens, outputTokens },
            };
          },
          Effect.timeoutOrElse({
            duration: TIMEOUT,
            orElse: () => Effect.fail(new ExtractError({ reason: "timeout" })),
          }),
        ),
      }),
    );

  /** No model configured: every extraction fails as unavailable. */
  static readonly layerNone = Layer.succeed(
    RecipeExtractor,
    RecipeExtractor.of({
      available: false,
      extract: () => Effect.fail(new ExtractError({ reason: "unavailable" })),
    }),
  );

  /**
   * AI_PROVIDER picks the adapter (gemini, anthropic or openai; by default the
   * first of those whose key is set) and AI_MODEL the model. Without a key,
   * imports still work for sources that need no model (JSON-LD pages, clearly
   * laid out text).
   */
  static readonly layer = Layer.unwrap(
    Effect.gen(function* () {
      const names = Object.keys(PROVIDERS) as Array<ProviderName>;
      const keys = {} as Record<ProviderName, Option.Option<Redacted.Redacted<string>>>;
      for (const name of names) {
        keys[name] = yield* Config.option(Config.Redacted(PROVIDERS[name].key));
      }
      const chosen = yield* Config.option(Config.Literals(names, "AI_PROVIDER"));
      const model = yield* Config.option(Config.String("AI_MODEL"));
      const name = Option.getOrUndefined(chosen) ?? names.find((n) => Option.isSome(keys[n]));
      if (name === undefined) {
        yield* Effect.logInfo("No model configured: Distill uses structured data and text only.");
        return RecipeExtractor.layerNone;
      }
      const apiKey = keys[name];
      if (Option.isNone(apiKey)) {
        return yield* Effect.die(`AI_PROVIDER is ${name}, but ${PROVIDERS[name].key} isn't set.`);
      }
      return RecipeExtractor.layerModel({
        name,
        apiKey: apiKey.value,
        model: Option.getOrElse(model, () => PROVIDERS[name].model),
      });
    }),
  );

  /**
   * A fake model for tests: `respond` sees what the model would and answers
   * with a recipe, an outcome without one, or an ExtractError. Usage is
   * logged as the input's length in and 100 tokens out.
   */
  static readonly layerTest = (
    respond: (input: ExtractInput) => Effect.Effect<ExtractedRecipe | ExtractOutcome, ExtractError>,
  ) =>
    Layer.succeed(
      RecipeExtractor,
      RecipeExtractor.of({
        available: true,
        extract: Effect.fn("RecipeExtractor.extract")(function* (input) {
          const answer = yield* respond(input);
          const usage = { model: "fake", inputTokens: input.text.length, outputTokens: 100 };
          return typeof answer === "string"
            ? { outcome: answer, recipe: emptyExtracted, usage }
            : { outcome: "found" as const, recipe: answer, usage };
        }),
      }),
    );
}
