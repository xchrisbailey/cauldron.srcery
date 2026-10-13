# Cauldron native: AI

Decision 27: Gemini Flash does the heavy AI, called straight from the device with Chris's own key. There is no server. The code is in `apple/CauldronKit/Sources/CauldronKit/AI/` (prompts, answer shapes, Gemini mapping, the rules) and `apple/Cauldron/AI/` (the key, the network, the on-device model, the queue).

## What goes where

- **`RecipeAI`** is the protocol: read a recipe out of text, estimate a recipe's macros, estimate a described meal. `GeminiRecipeAI` is the provider. A Private Cloud Compute provider can be added behind the same protocol later.
- **`RecipeAIService`** is what the app talks to. It holds `status`, which views show as a line that stays (in Settings and beside AI actions), never as an alert.
- **Prompts and answer shapes** are carried over from `apps/api/src/imports/RecipeExtractor.ts` word for word. Gemini is asked for JSON with a `responseSchema`. An answer missing any key is refused, as the reference's schema refuses it.

## The key

- Entered once in Settings and saved in the keychain as synchronizable, so iCloud Keychain carries it to the Mac. It is never compiled in, logged or exported, and it travels only in the `x-goog-api-key` header, never in a URL.
- Synchronizable items need the keychain entitlement that comes with signing (#162). A build without it keeps the key on that device only.
- The model defaults to `gemini-3.5-flash-lite` and can be changed in Settings.

## When Gemini can't be reached

"Can't be reached" means no key, a refused key, a spent quota (429), no connection, a timeout or a 5xx.

- **Reading a recipe falls back** to Apple's on-device model, and the result is marked `rough` so the cook is told to check it. Long text is trimmed to fit. A device with no on-device model reports why Gemini wasn't used.
- **Macro estimates never fall back.** They wait in the queue (`AIJobRecord`) and the recipe or diary entry shows as pending. The queue runs when the app comes forward, when the network comes back, and when a key is saved. A job waits for as long as Gemini is out of reach without using up attempts.
- **A bad answer from Gemini is a failure, not a reason to fall back.** A queued job gets three attempts at a bad answer, then is marked failed and stops showing as pending.
- Macros the cook typed in while an estimate waited are kept.

## Not verified yet

- A real call to Gemini. The request and response mapping is tested against response bodies written by hand from Gemini's documented shapes, not recorded from the live API.
- The on-device fallback on a device. The simulator has no model.
- The key reaching a second device through iCloud Keychain.
