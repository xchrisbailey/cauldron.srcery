# Cauldron

A personal recipe box, weekly meal planner and macro tracker, by srcery. It is a native iOS 27 / macOS 27 SwiftUI app with no server. The plan lives in the native epic, [#157](https://github.com/xchrisbailey/cauldron.srcery/issues/157). Every ticket is a sub-issue of it and says what it depends on and when it's done. The decisions behind the plan are in `docs/native/decisions.md`, and the phases in `docs/native/plan.md`.

## Stack

- **App** (`apple/Cauldron`): one multiplatform SwiftUI target for iPhone, iPad and Mac. Bundle ID `computer.srcery.cauldron`. Swift 6 language mode with complete strict concurrency, and warnings are errors.
- **CauldronKit** (`apple/CauldronKit`): a local Swift package holding the domain logic: the ingredient line parser, units and scaling, macro maths, adaptive targets and the copy module. It is pure Swift over plain value types. It never imports UIKit, AppKit, SwiftUI or SwiftData, so it builds and tests on Linux.
- **Data**: SwiftData, synced through the iCloud private database `iCloud.computer.srcery.cauldron`. Views read with `@Query`.
- **State**: Observation (`@Observable`), not `ObservableObject`.
- **AI**: Gemini Flash called directly from the device, behind the `RecipeAI` protocol. Chris's key is pasted into Settings and held in the Keychain. Recipe parsing falls back to Apple's on-device model and is marked rough. Macro estimates are queued until Gemini is reachable, never guessed.
- **Tests**: Swift Testing (`import Testing`, `@Test`, `#expect`) in both the package (`apple/CauldronKit/Tests`) and the app (`apple/CauldronTests`).
- **Lint and format**: Apple's `swift-format`, configured in `apple/.swift-format`.

## Layout

```
apple/
  project.yml            the Xcode project's source of truth (XcodeGen)
  Cauldron.xcodeproj     generated from project.yml, and committed
  Cauldron/              the app; a synced folder, so new files need no project change
  CauldronTests/         the app's tests; also a synced folder
  CauldronKit/           the Swift package
  .swift-format
Makefile                 the local checks
docs/native/             decisions and plan
```

To add a target, a capability or a build setting, edit `apple/project.yml` and run `make project`. Don't edit `project.pbxproj` by hand. `project.yml` spells out every build setting, so it does not rely on XcodeGen's presets.

## Commands

Run these from the repo root. There is no CI for tests or lint, so run `make ready` before pushing.

- `make lint`, `make format`: `swift-format` over the app and the package.
- `make test`: CauldronKit's tests, then the app's tests as a Mac app. `make test-kit` and `make test-app` run one half each.
- `make test-ios`: the app's tests on the iPhone simulator (`SIMULATOR="iPhone 18 Pro"` by default).
- `make build`: builds the app for the Mac and the iPhone simulator.
- `make project`: regenerates `apple/Cauldron.xcodeproj`.
- `make ready`: lint, `test` and `test-ios`.

**Where work runs.** Cloud sessions run on Linux and can only build and test `CauldronKit` (`make lint`, `make test-kit`). Anything that touches the app target runs on Chris's Mac, through a Remote Control session in the cauldron folder, where it can be built and launched on the simulator and as a Mac app. A cloud session that needs an app build stops and says so.

**CI/CD ships TestFlight only**, through Xcode Cloud on `v*` tags. Don't add GitHub workflows.

## Conventions

- **Domain logic goes in CauldronKit**, as pure functions over value types that are `Sendable`. The app holds views, SwiftData models and services. If a rule can be tested without a view or a store, it belongs in the package.
- **Services sit behind protocols.** Every external dependency (AI, network fetches, HealthKit, the Keychain, the clock) is a protocol with a real implementation and a test double. Tests use the doubles and an in-memory `ModelContainer`. They never reach the network or iCloud.
- **SwiftData models must stay CloudKit-compatible**: every property optional or defaulted, every relationship optional, and no `@Attribute(.unique)`. Once synced data exists, schema changes are additive only.
- **Ingredients** are always stored structured (quantity, unit, item, note, original line). Never store only a free-text blob.
- **Concurrency**: no `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` to quiet the compiler without a comment that says why it is safe.
- **No force unwraps, `try!` or implicitly unwrapped optionals.** The lint enforces this.
- **Copy**: every user-facing string comes from the copy module in CauldronKit and is marked `voice` or `plain`. The rule is magic verbs with plain nouns. Errors, quantities, step controls and the literal part of delete confirmations are always plain.
- **Brand**: Catppuccin Latte (light) and Mocha (dark), Geist and Geist Mono. Colours live in the asset catalogue and are read through `Brand.Colors`. There are no raw colour values in Swift. Type goes through `brandStyle(_:)`, and every quantity, unit, time and date is set in Geist Mono (`QuantityText`, or the `.quantity` and `.unit` styles). The colour sets and app icons are generated: change `apps/web/src/styles/tokens.css` or `brand/build.ts`, then run `bun run brand`. Don't edit them by hand. Debug builds have a Brand screen to check against the [brand book](https://claude.ai/artifact/G1C5x9s76ey5iEN6sbhMgu).
- **Native structure**: tab bar, lists, sheets and swipe actions on iPhone, and a sidebar, menus and keyboard shortcuts on the Mac, in the same target.
- **Secrets**: the Gemini key is never compiled into the app or committed. It lives in the Keychain.

## The frozen TypeScript workspace

`apps/`, `packages/` and the root `package.json` are the old web app and API (Effect 4, TanStack Start, Drizzle). They are frozen as the reference implementation. Don't add features to them or change them. When porting, the TypeScript behaviour and its tests are the specification: port tests case for case, and where the Swift differs it is wrong unless the PR says why. To run the reference tests, use `bun install` and `bun run test`. The workspace is tagged `web-final` and removed once the native app reaches parity (#186).

## Delegation

The main session runs on **Opus at medium effort** (`.claude/settings.json`). It plans, orchestrates, reviews, and does the larger or cross-cutting work itself: architecture, the Xcode project, the SwiftData schema, and anything touching both the app and CauldronKit. Everything else goes to the agents in `.claude/agents/`:

- `coder` (Sonnet 5.5, high): one ticket or a bounded piece of one, code and tests, in its own worktree, ending in a draft PR.
- `scout` (Haiku): read-only lookups for writing a brief.
- `adversary` (Fable): tries to break a ticket breakdown or a risky PR.
- On an agent team, `reviewer` (Sonnet 5.5, high) gives each draft PR a first pass and `shepherd` (Haiku) reruns checks and cleans up after merges.

A session spawned as one of these follows its own file instead. Opus reviews every PR before it is marked ready. When delegating a ticket, starting an agent team, stacking or merging PRs, or reviewing a coder's PR, read `docs/agents/orchestration.md`.

Subagents without a named type default to Sonnet 5.5 (`CLAUDE_CODE_SUBAGENT_MODEL`). Subagents start cold, so every brief stands alone.
