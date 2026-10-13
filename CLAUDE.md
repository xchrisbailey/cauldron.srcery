# Cauldron

A personal recipe box, weekly meal planner and macro tracker, by srcery. It is a native iOS 27 / macOS 27 SwiftUI app with no server, built for Chris and installed through TestFlight. The plan lives in the native epic, [#157](https://github.com/xchrisbailey/cauldron.srcery/issues/157): every ticket is a sub-issue of it and says what it depends on and when it's done. The decisions behind it are in `docs/native/decisions.md`.

## Layout

- `apple/Cauldron`: the multiplatform SwiftUI app (bundle ID `computer.srcery.cauldron`), one target for iPhone and Mac. `apple/CauldronTests` holds its tests.
- `apple/CauldronKit`: a local Swift package with the domain logic: the ingredient line parser, units and scaling, macro maths, adaptive targets, dates, timers and the copy module. It imports no UIKit, AppKit, SwiftUI or SwiftData, so it builds and tests on Linux.
- `apple/project.yml`: the source of the Xcode project. `Cauldron.xcodeproj` is generated from it with XcodeGen and committed (Xcode Cloud needs it). Source folders are synced, so a new Swift file needs no project change. Edit `project.yml` for targets, settings, capabilities and packages, run `make project`, and commit both.
- `docs/native`: decisions, plan, and how-to notes.
- `apps/`, `packages/`, `brand/build.ts` and the Bun tooling: the old TypeScript web app and API, **frozen** as the reference implementation. Read it to port behaviour and tests; don't add features to it. It is removed at parity (#186). Its conventions are in the `web-final` history of this file, and `bun run test` still runs its suite.

## Stack

- **Swift 6 language mode with strict concurrency**, on iOS 27 and macOS 27 only.
- **UI**: SwiftUI with Observation (`@Observable`, no `ObservableObject`). Native structure in srcery style: a tab bar on iPhone, a sidebar on Mac, lists, sheets and swipe actions.
- **Data**: SwiftData, read in views with `@Query`, synced through the iCloud private database `iCloud.computer.srcery.cauldron`. There are no accounts and no sharing.
- **AI**: Gemini Flash, called straight from the device behind the `RecipeAI` service, with Chris's own key from the Keychain (decision 27; see `docs/native/ai.md`). Recipe parsing falls back to Apple's on-device model when Gemini can't be reached and is then marked rough. Macro estimates are queued until Gemini is back, and never guessed.
- **Tests**: Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- **Lint and format**: Apple `swift-format`, configured in `apple/.swift-format`.
- **CI/CD**: Xcode Cloud ships TestFlight builds on `v*` tags and does nothing else. Tests and lint run locally.

## Commands

Run these from `apple/`:

- `make ready`: lint, then every test. Run it before reporting work done.
- `make format` rewrites sources; `make lint` fails on anything it would change and on lint rules.
- `make test-kit`: `swift test` for `CauldronKit`. This is the only one that runs on Linux.
- `make test-mac`, `make test-ios`: the app's tests on macOS and on the iOS simulator (`IOS_SIMULATOR` overrides the destination).
- `make build`: build the app for both platforms. `make project`: regenerate the Xcode project from `project.yml`.

**Where work can run.** Cloud sessions are on Linux: they build and test `CauldronKit` only (`swift build` and `swift test` in `apple/CauldronKit`) and can't build the app. Anything that touches the app target, SwiftData, the simulator, a device, signing or TestFlight runs on Chris's Mac. A ticket whose "Done when" needs a device or a second iCloud device is finished by Chris; say plainly which checks you ran and which are his.

## Build order

Follow the "Depends on" line at the top of each ticket. Phase 0 (#159 to #162) is the foundation and Phase 1 (#163 to #165) fills `CauldronKit`; the screens in Phases 2 to 5 sit on both. The ingredient line parser feeds the editor, every importer and the Gather list, so keep it strict and port its whole test corpus.

## Conventions

- **Port, don't reinvent.** For anything the web app did, the TypeScript is the reference. Port its tests case for case; where Swift behaves differently, Swift is wrong unless the ticket's PR says why.
- **Domain logic lives in `CauldronKit`** as pure functions over plain `Sendable` value types. No SwiftData models, no views and no Apple-only frameworks in it. Use Foundation only where swift-corelibs-foundation has it on Linux.
- **Services behind protocols.** Every external dependency (the AI model, HealthKit, network fetches, the clock, notifications) is a protocol with a live implementation and a test double. Views and models get them through the SwiftUI environment or an initialiser. Tests use the doubles and an in-memory `ModelContainer`, never the real service.
- **SwiftData models must stay CloudKit-compatible**: every property optional or defaulted, every relationship optional with an inverse, no `@Attribute(.unique)`. Photos use `.externalStorage`. Once data has synced, schema changes are additive only.
- **Only `CauldronStore` opens a store.** Get every `ModelContainer` from `CauldronStore.container(_:)`, and use `.inMemory` in tests and previews. Never create one with a default configuration: SwiftData's default file is shared between unsandboxed Mac apps, and opening it once rewrote another app's data. `make lint` rejects a container made anywhere else, and the Mac app stays sandboxed. Don't write outside the repo, the app's container or the scratch directory from code or tests.
- **Ingredients** are always stored structured (quantity, unit, item, note, original line). Never store only a free-text blob.
- **Copy**: every user-facing string comes from the copy module in `CauldronKit` and is marked `voice` or `plain`. The rule is magic verbs with plain nouns. Errors, quantities, step controls and the literal part of delete confirmations are always plain. No string literals in views.
- **Brand**: colours live in the asset catalogue (the only place with raw colour values) and are read through `Brand.Colors`. Catppuccin Latte is the light appearance and Mocha the dark one. Type goes through the brand `Font` helpers: Geist for text, and Geist Mono for every quantity, unit, time and date. Follow the [brand book](https://claude.ai/artifact/G1C5x9s76ey5iEN6sbhMgu).
- **Concurrency**: UI state is `@MainActor`. Don't silence the compiler with `@unchecked Sendable` or `nonisolated(unsafe)`; fix the isolation.
- **No force unwraps, `try!` or implicitly unwrapped optionals** outside tests (the linter enforces it).
- **Both platforms, both appearances.** A screen isn't done until it works on iPhone and Mac in light and dark. Use `#if os(...)` sparingly and keep it at the edge of a view.
- **Dependencies**: prefer Apple frameworks. A third-party package needs a reason in the PR, and one in `CauldronKit` must build on Linux.

## Delegation

The main session runs on **Opus at medium effort** (`.claude/settings.json`). It plans, orchestrates, reviews, and does the larger or cross-cutting work itself: architecture, the SwiftData schema and anything that changes it, `project.yml` and targets, entitlements and signing. Everything else goes to the agents in `.claude/agents/`:

- `coder` (Sonnet 5.5, high): one ticket or a bounded piece of one, code and tests, in its own worktree.
- `scout` (Haiku): read-only lookups for writing a brief.
- `adversary` (Fable): tries to break a ticket breakdown or a risky change.
- On an agent team, `reviewer` (Sonnet 5.5, high) gives each draft PR a first pass and `shepherd` (Haiku) reruns checks and cleans up after merges.

A session spawned as one of these follows its own file instead. Opus reviews every change before it is merged or marked ready. When delegating a ticket, starting an agent team, working on an integration branch, stacking or merging PRs, or reviewing a coder's work, read `docs/agents/orchestration.md`.

Subagents without a named type default to Sonnet 5.5 (`CLAUDE_CODE_SUBAGENT_MODEL`). Subagents start cold, so every brief stands alone.
