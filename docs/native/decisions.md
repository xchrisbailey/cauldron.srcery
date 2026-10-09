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
