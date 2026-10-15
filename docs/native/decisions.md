# Cauldron native: decisions

Grilling session with Chris, started 2026-10-09. Background and costs: [ios-switch-cost.md](ios-switch-cost.md).

## Round 1 (2026-10-09)

1. **Data lives on the device.** SwiftData synced through iCloud (CloudKit private database), Apple Foundation Models for AI (on-device + iOS 27 Private Cloud Compute). No server.
2. **The web app and API are retired** once the native app ships.
3. **Audience: Chris only for now**, installed via TestFlight/Xcode, but built clean enough to submit to the App Store later.
4. **No households or sharing, at all.** Dropped, not deferred.
5. **Full parity in the native app**: recipes, Distill imports, Brew, Week planner, Gather list, macro tracker (diary, describe-it, log a recipe, recents/favourites, weigh-ins, targets, adaptive targets), plus HealthKit.

## Round 2 (2026-10-09)

6. **iOS 27 and macOS 27 minimum.** Needed for the Private Cloud Compute model.
7. **Same repo** (xchrisbailey/cauldron.srcery). Tag the last TypeScript version, then remove it and put the Xcode project in.
8. **Start fresh.** No data migration. Demo data appears only in debug builds.
9. **Mac app is multiplatform SwiftUI** in the same target, with Mac layout (sidebar, menus, shortcuts) from day one, shipping alongside iPhone.
10. **When AI is unavailable:** recipe parsing falls back to the on-device model and the result is marked rough. Macro estimates are queued and finished later, never guessed.
11. **Hosting is dropped.** Close deploy PRs #153–#155 and #21 as not planned. The web app is never deployed.
12. **HealthKit:** read weight, and write eaten energy, protein, carbs and fat. Don't read active energy.
13. **Look and feel:** native iOS/macOS structure (tab bar, lists, sheets, swipe actions) in srcery style, with Catppuccin Mocha/Latte, Geist and Geist Mono, and the brand voice.

## Round 3 (2026-10-09)

14. **Apple Developer Program: Chris already has an account.**
15. **Code layout:** a pure Swift package `CauldronKit` holds the parser, scaling, macro maths, adaptive targets and copy, with the multiplatform app on top. Cloud threads can build and test `CauldronKit` on Linux.
16. **Builds:** Remote Control sessions on Chris's Mac (cauldron folder) build the app and run it on the simulator and devices.
17. **TypeScript stays on main until parity.** Then tag `web-final` and remove it in one PR.
18. **New import source:** photograph a recipe (on-device text recognition, then the same AI parsing). This is added to URL, share sheet and paste.
19. **Native extras in v1:** a Brew Live Activity (Lock Screen timers) and a today's-macros widget. Siri/Shortcuts come later.
20. **Backup:** JSON export in Settings.
21. **Tracking:** a new native epic replaces #22, with tickets in the existing format. Close #17 (video transcription) and #24 (households) as not planned.
22. **CI/CD is for TestFlight releases only.** Tests, lint and format run locally on Chris's Mac, not in CI.

## Round 4 (2026-10-09)

23. **TestFlight ships from Xcode Cloud**, triggered by a `v*` tag.
24. **Remove the existing GitHub workflows now** (PR CI and the weekly live-import check).
25. **Name "Cauldron"**, bundle ID `computer.srcery.cauldron`, iCloud container `iCloud.computer.srcery.cauldron`.
26. **Conventions:** Swift 6 strict concurrency, SwiftUI with Observation, SwiftData `@Query`, Swift Testing, Apple `swift-format` (run locally). CLAUDE.md is rewritten for the Swift stack in the first native PR.

## Round 5 (2026-10-12)

27. **Gemini Flash does the heavy AI for now** (recipe extraction, divine macros, describe-it), not Apple's Private Cloud Compute model. Chris is putting off the PCC entitlement, which needs App Store Small Business Program enrolment. The app calls the Gemini REST API directly from the device (`gemini-3.5-flash-lite` by default, overridable in Settings) with structured JSON output. There's still no server.
    - **The key is never compiled into the app.** Chris pastes his Gemini API key into Settings once. It's stored in the Keychain with iCloud Keychain sync, so iPhone and Mac both get it.
    - `RecipeAI` stays a protocol with a Gemini provider now. A PCC provider can be added later behind the same interface without touching callers.
    - The decision 10 rules still apply with Gemini as the primary: offline or no key means recipe parsing falls back to the on-device model (marked rough), and macro estimates are queued.
    - Decision 6 (iOS/macOS 27 minimum) stays, since SwiftData and on-device Foundation Models want it and PCC may come back.

## Round 6 (2026-10-14)

28. **Any AI provider the cook has a key for.** Gemini, OpenAI or Claude, chosen in Settings, each with its own Keychain key; the cheapest capable model is the default for each (Gemini Flash-Lite, GPT Luna, Claude Haiku). Decision 27's rules carry over to whichever is chosen.
29. **The week starts on any day**, chosen in Settings and synced (the web offered Monday or Sunday, kept per browser). Stirring a recipe into the week can spread it over several days, one serving a day by default for meal prep.

## Round 7: parity (2026-10-15)

The #186 audit read the web app against the native one, area by area. Chris's calls:

30. **Fixed to match the web:** copy a diary day or meal; duplicate a recipe; filter the library by tag and rename a tag, with "Clear filters"; mark brewed from the recipe page; log a recipe from Brew's last step; tick off ingredients on the recipe page; print a recipe; fix and reset a misread ingredient line in the editor; add or change a step timer; keep an unfinished new recipe and offer to restore it; field errors shown on leaving the field; ⌘K quick-open on the Mac; an import's macros estimated into the draft for review (queued only when the AI can't be reached); the web's limits on queued estimate input; Brew using the page's unit choice, which is remembered; a dropped recipe going through the spread step and landing where it was dropped; search covering descriptions and plurals, with the web's sort tie-break; Brew without steps offering Edit; free-text meal titles counted as the web counts them.
31. **Units are metric by default** (cm, kg) on every screen, as on the web, until the cook chooses otherwise.
32. **Dropped:** the library's grid/list toggle. The native list of cards stays.
33. **Gone with the server (decisions 1, 2, 11 and 27):**
    - Instagram captions come from the post page's preview tags only; the web read them through Meta's oEmbed with a token, which needs a server.
    - Imports run on the device, inside the import sheet: no job queue that survives a relaunch, no 100-a-day import budget (the provider's own rate limit applies), and the import text isn't kept for seven days.
    - Accounts, sign-in, households, hosting, rate limiting and the photo upload pipeline (decisions 1, 2, 4 and 11).
