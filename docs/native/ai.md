# Cauldron native: AI

Decision 27: a cloud model does the heavy AI, called straight from the device with the user's own key. There is no server. Gemini is the default; OpenAI and Claude are there for a user who already has one of those keys. The code is in `apple/CauldronKit/Sources/CauldronKit/AI/` (prompts, answer shapes, each provider's request and response mapping, the rules) and `apple/Cauldron/AI/` (the keys, the network, the on-device model, the queue).

## What goes where

- **`RecipeAI`** is the protocol: read a recipe out of text, estimate a recipe's macros, estimate a described meal. `CloudRecipeAI` is the cloud implementation for all three providers: it takes an `AIProvider`, and the Kit builds that provider's request and reads its response. A Private Cloud Compute provider can be added behind the same protocol later.
- **`RecipeAIService`** is what the app talks to. It holds the chosen provider (`ai.provider` in `UserDefaults`, Gemini until the user picks another) and `status`, which views show as a line that stays (in Settings and beside AI actions), never as an alert. Nothing outside it and Settings knows which provider is in use. Switching provider re-reads that provider's key, resets the status as saving a key does, and runs the queue.
- **Prompts and answer shapes** are carried over from `apps/api/src/imports/RecipeExtractor.ts` word for word, and are the same for every provider. The shape is written once (`AISchema`) and rendered twice: as Gemini's `responseSchema`, and as strict JSON Schema for OpenAI and Claude (every object closed with `additionalProperties: false`, every property required, a nullable field as `["string", "null"]`). An answer missing any top-level key is refused, as the reference's schema refuses it. (A line or step without its `section` key is read as having none.)

## The providers

| | Gemini | OpenAI | Claude |
| --- | --- | --- | --- |
| Endpoint | `generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` | `api.openai.com/v1/responses` | `api.anthropic.com/v1/messages` |
| Key header | `x-goog-api-key` | `Authorization: Bearer` | `x-api-key` (with `anthropic-version`) |
| Structured output | `generationConfig.responseSchema` | `text.format` of type `json_schema`, `strict: true` | `output_config.format` of type `json_schema` |
| Default model | `gemini-3.5-flash-lite` | `gpt-6-luna` | `claude-haiku-5-5` |
| Model setting | `ai.geminiModel` | `ai.model.openai` | `ai.model.anthropic` |

- Each URL is fixed and https. OpenAI and Claude take the model in the body, so a model name can't change where a request goes; Gemini's goes in the URL, so it is checked to be letters, digits and `-._`. An empty model name is refused for every provider.
- The model is overridable per provider in Settings; empty means the default. Gemini's setting keeps the key it had before there were other providers, so a model set then still holds.
- OpenAI requests set `store: false`, so the response isn't kept on OpenAI's side.
- Claude defaults to Claude Haiku 5.5: these are small, frequent jobs, and it costs a fortieth of Claude Opus 5.5. Requests ask for `effort: low` and send no `thinking`, `temperature`, `top_p` or prefilled reply, which current Claude models reject. When the cook names a model that has a server-side fallback (Claude Fable 5.1, Opus 5.5, Opus 5, Sonnet 5.5), the request also carries `fallbacks: "default"` with the `anthropic-beta: server-side-fallback-2026-07-01` header, so a decline is answered by another model. Haiku has no server-side fallback, so its requests go without it.
- Errors map the same way for all three: a refused key (401, 403) is `invalidKey`; a spent quota or limit (429, and for Claude 402) is `rateLimited`; 404 is `invalidModel`; a timeout, a status that isn't HTTP and a 5xx (Claude's 529 overload too) is `unreachable`; any other 4xx is a failure that names the error's `code` or `type`, never its message. A refusal, an unfinished response and a cut-off answer are failures too.
- "Sign in with ChatGPT" is not used: OpenAI documents plan usage for open-source and locally hosted apps only, with an interest form for others.

## The keys

- One keychain item per provider (`computer.srcery.cauldron.gemini`, `.openai`, `.anthropic`; account `api-key`). Gemini's is the item the app has always used, so a key saved before the other providers existed is still found. Switching provider never touches another provider's key.
- Entered once in Settings and saved in the keychain as synchronizable, so iCloud Keychain carries it to the Mac. It is never compiled in, logged or exported, and it travels only in its provider's header, never in a URL or a body, and is in no error. Redirects are refused, so the header can't follow one to another host.
- Synchronizable items need the keychain entitlement that comes with signing (#162). A build without it keeps the key on that device only.

## When the AI can't be reached

"Can't be reached" means no key, a refused key, a spent quota, a model name the provider doesn't know (404), no connection, a timeout or a 5xx. Each of the first four leaves its own line in Settings, naming the provider, until it next answers. The rules below are the same for every provider.

- **Reading a recipe falls back** to Apple's on-device model, and the result is marked `rough` so the cook is told to check it. Long text is trimmed to fit. A device with no on-device model reports why the provider wasn't used.
- **Macro estimates never fall back.** They wait in the queue (`AIJobRecord`) and the recipe or diary entry shows as pending. The queue runs when the app comes forward, when the network comes back, when a key is saved and when the provider is switched. A job waits for as long as the provider is out of reach without using up attempts.
- **A bad answer from the provider is a failure, not a reason to fall back.** A queued job gets three attempts at a bad answer, then is marked failed and stops showing as pending.
- Macros the cook typed in while an estimate waited are kept.
- **A cancelled request is not "unreachable".** It doesn't fall back and doesn't use an attempt.

## The queue

- **One drain at a time.** A drain asked for while one is running makes that one go round again; it doesn't start a second.
- **A job never adds rows.** Jobs sync, so the same job can run on two devices before either hears from the other. What a job writes reads the same however often it is written: a recipe's macros, or one diary entry's.
- **A described meal stays one entry.** The entry keeps the cook's words as its name and gets its foods' numbers added up. Splitting a described meal into separate foods is for the screen that asks while online (#179), where the cook confirms them.
- **A job whose recipe or entry can't be found waits a week before it is dropped.** Over sync the job can arrive first.
- **Anything marked as waiting with no job gets a new one** at the next drain. That covers an entry removed and put back, and a job deleted on another device.

## Not verified yet

- The key on a Mac build without the keychain entitlement. Saving falls back to a key kept on that Mac only, and whether reading finds it there has not been tried on a Mac.

- A real call to any provider. Each request and response mapping is tested against response bodies written by hand from the provider's documented shapes, not recorded from the live API. OpenAI's and Claude's models and Claude's fallback header in particular have not been tried against the live services.
- The on-device fallback. It has only been compiled, never run against Apple's model, so its prompts and trimming are untested.
- The key reaching a second device through iCloud Keychain.
