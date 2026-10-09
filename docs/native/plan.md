# Cauldron native: plan

From the decisions in [decisions.md](decisions.md) (2026-10-09). This plan becomes a new epic that replaces #22, with tickets in the existing format ("Depends on", "Done when").

**Shape:** an iOS 27 / macOS 27 multiplatform SwiftUI app. Data is in SwiftData synced through the iCloud private database. AI runs on Apple Foundation Models (Private Cloud Compute, falling back to on-device), with no server. A pure Swift package `CauldronKit` holds the domain logic and is tested on Linux by cloud threads and locally by Chris. App builds run through Remote Control on Chris's Mac. Xcode Cloud ships TestFlight on `v*` tags. It has full parity with the web app, then the TypeScript is removed.

## Phase 0: Foundation
- **Housekeeping:** close #17, #24, #21 and deploy PRs #153–#155 as not planned. Remove `.github/workflows`. File the native epic and its tickets.
- **Project skeleton:** Xcode multiplatform app (`computer.srcery.cauldron`), the `CauldronKit` package, `swift-format` config, Swift 6 strict concurrency. Rewrite CLAUDE.md for the Swift stack.
- **Data model:** SwiftData models for recipes (structured ingredients), photos, plan entries, gather items, diary entries, foods/favourites, weigh-ins and targets. Must be CloudKit-compatible (optional or defaulted properties, no unique constraints). Debug-only demo seed.
- **Brand in Swift:** Catppuccin Mocha/Latte colour assets, bundled Geist and Geist Mono, type and quantity styles, app icon from `brand/`.
- **TestFlight:** Xcode Cloud workflow on `v*` tags, plus iCloud, HealthKit and Foundation Models PCC entitlements. Applying for the PCC entitlement starts here.

## Phase 1: CauldronKit ports (Linux-testable, can run in parallel)
- Ingredient line parser, ported with its full test corpus from `packages/shared`.
- Units and scaling.
- Copy module (voice/plain), carried over as is.
- Brewing timers.
- Macro calculator (Mifflin-St Jeor, activity, goal/rate, protein, fat floor, carbs) and plan macro tally.
- Adaptive targets.

## Phase 2: Recipes and Brew
- Recipe list, search and detail with the compact macro line.
- Editor with structured ingredients and photos (PhotosPicker, camera).
- Brew mode: steps, timers, screen kept awake, Lock Screen Live Activity.

## Phase 3: Imports and AI
- `RecipeAI` service: PCC model with `@Generable` output, falling back to on-device for parsing (marked rough). Macro estimates are queued when unavailable. Quota state is shown in the UI.
- Import by URL (on-device fetch and page extraction), by paste, and by photo (on-device text recognition).
- Share extension for Safari, Instagram and TikTok captions.
- "Divine macros" for recipes, run automatically on imports that have no page nutrition.

## Phase 4: Week and Gather
- Week calendar, servings spread across picked days, weekly and per-day macro tally.
- Gather list built from the week, merged by ingredient, checkable.

## Phase 5: Tracker
- Diary with meal slots and an eaten-vs-target header.
- Describe-it logging via AI (queued if unavailable), log a recipe × servings, recents and favourites.
- Targets set-up (calculator) and overrides.
- Weigh-ins with HealthKit read. Eaten macros written to HealthKit.
- Adaptive targets.
- Today's-macros widget.

## Phase 6: Mac, export, parity
- Mac layout pass: sidebar, menus, keyboard shortcuts, multi-window where useful.
- JSON export in Settings.
- Parity check against the web app, feature by feature.
- Tag `web-final`, then remove the TypeScript workspace in one PR.

## Risks to watch
- **PCC entitlement approval:** apply in Phase 0. On-device fallback keeps parsing working meanwhile.
- **CloudKit schema:** additive changes only once synced data exists, and deploy the schema to production before the first TestFlight build.
- **Macro estimate quality from Apple's model is untested.** Compare a sample against Gemini's results early in Phase 3.
