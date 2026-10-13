# Cauldron native: AI

Decision 27: Gemini Flash does the heavy AI, called straight from the device with Chris's own key. There is no server. The code is in `apple/CauldronKit/Sources/CauldronKit/AI/` (prompts, answer shapes, Gemini mapping, the rules) and `apple/Cauldron/AI/` (the key, the network, the on-device model, the queue).

## What goes where

- **`RecipeAI`** is the protocol: read a recipe out of text, estimate a recipe's macros, estimate a described meal. `GeminiRecipeAI` is the provider. A Private Cloud Compute provider can be added behind the same protocol later.
- **`RecipeAIService`** is what the app talks to. It holds `status`, which views show as a line that stays (in Settings and beside AI actions), never as an alert.
- **Prompts and answer shapes** are carried over from `apps/api/src/imports/RecipeExtractor.ts` word for word. Gemini is asked for JSON with a `responseSchema`. An answer missing any top-level key is refused, as the reference's schema refuses it. (A line or step without its `section` key is read as having none.)

## The key

- Entered once in Settings and saved in the keychain as synchronizable, so iCloud Keychain carries it to the Mac. It is never compiled in, logged or exported, and it travels only in the `x-goog-api-key` header, never in a URL. Redirects are refused, so the header can't follow one to another host.
- Synchronizable items need the keychain entitlement that comes with signing (#162). A build without it keeps the key on that device only.
- The model defaults to `gemini-3.5-flash-lite` and can be changed in Settings.

## When Gemini can't be reached

"Can't be reached" means no key, a refused key, a spent quota (429), a model name Gemini doesn't know (404), no connection, a timeout or a 5xx. Each of the first four leaves its own line in Settings until Gemini next answers.

- **Reading a recipe falls back** to Apple's on-device model, and the result is marked `rough` so the cook is told to check it. Long text is trimmed to fit. A device with no on-device model reports why Gemini wasn't used.
- **Macro estimates never fall back.** They wait in the queue (`AIJobRecord`) and the recipe or diary entry shows as pending. The queue runs when the app comes forward, when the network comes back, and when a key is saved. A job waits for as long as Gemini is out of reach without using up attempts.
- **A bad answer from Gemini is a failure, not a reason to fall back.** A queued job gets three attempts at a bad answer, then is marked failed and stops showing as pending.
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

- A real call to Gemini. The request and response mapping is tested against response bodies written by hand from Gemini's documented shapes, not recorded from the live API.
- The on-device fallback. It has only been compiled, never run against Apple's model, so its prompts and trimming are untested.
- The key reaching a second device through iCloud Keychain.
