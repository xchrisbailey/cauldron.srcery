# Cauldron

A personal recipe box and weekly meal planner, by srcery. The web app comes first, followed by an iOS app and macro tracking. The plan lives in the v1 epic, [#2](https://github.com/xchrisbailey/cauldron.srcery/issues/2). Every ticket is a sub-issue of it and says what it depends on and when it's done.

## Native rebuild under way

Cauldron is being rebuilt as a native iOS 27 / macOS 27 SwiftUI app with no server (SwiftData + iCloud, Apple Foundation Models). The decisions and phased plan are in `docs/native/` and the native epic on GitHub. The TypeScript workspace below is frozen as the reference implementation: don't add features to it. It is removed once the native app reaches parity. CI/CD is only for TestFlight releases; tests, lint and format run locally.

## Stack

- **Monorepo**: Vite+ (`vp`) on Bun. It provides dev, build, Vitest, Oxlint, format and the task runner.
- **API** (`apps/api`): Effect 4 `HttpApi` on Bun (`@effect/platform-bun` `BunHttpServer`) under `/v1`. Postgres through Drizzle, wrapped as an Effect service.
- **API definition** (`packages/api-spec`): endpoints and groups only, with no handlers. The web app imports it to build a typed `HttpApiClient`, and the OpenAPI spec (the future iOS contract) is generated from it.
- **Shared** (`packages/shared`): Effect Schemas for the domain, the ingredient line parser, units and scaling, and the copy module.
- **DB** (`packages/db`): Drizzle schema, migrations and seed.
- **Web** (`apps/web`): TanStack Start + Router + Query, styled with StyleX using the brand tokens.
- **Auth**: Better Auth, mounted on `/v1/auth/*` through `HttpEffect.fromWebHandler`. Sessions reach handlers through an `HttpApiMiddleware` that provides `CurrentUser`.
- **AI**: TanStack AI, called from the API and wrapped as an Effect service (`RecipeExtractor`).

## Commands

- `bun run dev`: API on :3001 and web on :3000 (which proxies `/v1` to the API). Copy `apps/api/.env.example` to `apps/api/.env` first.
- `vp check` (`--fix` to fix): format, lint and typecheck across the workspace. `vp` alone runs Vite+ built-ins; `vpr <script>` runs a package script.
- `bun run test`, `bun run build`, `bun run ready` (run locally; there is no CI for the TypeScript any more).
- Locally the API uses PGlite (in-process Postgres); there is no Docker on the main dev machine.
- API tests build the whole app in process with `makeTestApi()` from `apps/api/test/helpers.ts`, on `Db.layerTest` (a fresh database: real Postgres when `DATABASE_URL` is set, PGlite otherwise) and `Mailer.layerTest`.
- The Effect language service is `@effect/tsgo`, patched into TypeScript 7 by the root `prepare` script, so `tsc -p <pkg>` also reports Effect diagnostics.

## Build order

Follow the "Depends on" line at the top of each ticket. The critical path:

1. **Spike first.** Before building #3 out, open one PR that proves the risky combination together: the Vite+ workspace, Effect HttpApi on Bun, the Better Auth bridge (including an OAuth callback), and a TanStack Start page styled with StyleX tokens that calls the API through `HttpApiClient` while signed in. If any piece fights back, stop and raise it on the epic before going further.
2. #3 scaffold, then #4 API foundation.
3. #5 auth and #6 data model, in parallel.
4. #1 brand tokens and assets must land before #7 web shell.
5. Phase 2 (#8 to #12), then Phase 3 imports (#13 first), then Phase 4 (#18 to #20). #21 deploy waits for the hosting decision.

The ingredient line parser in #6 feeds the editor, every importer and the Gather list. Give it its test corpus early and keep it strict.

## Effect 4

The `effect` version is pinned **exactly**. Upgrade on purpose, in its own PR. Most of what you remember about Effect is v3, and v4 renamed a lot. **Check v4 sources before writing Effect code**:

- The pinned package ships its own guide: `node_modules/effect/AGENTS.md`, with runnable examples in `node_modules/effect/ai-docs/src/` (HTTP server and its tests, HTTP client, SQL, AI, testing). Prefer these over the effect-smol repo, which can lag the release. With Bun's isolated installs, look under `apps/api/node_modules/effect/`.
- Migration notes: https://github.com/Effect-TS/effect-smol/tree/main/migration (start with `v3-to-v4.md` and `services.md`).
- When in doubt, read the source under `node_modules/effect/src` for the pinned version, and don't write it from memory.

The v3 habits that break most often:

| v3                                                 | v4                                                                                                                                     |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `Context.Tag`, `Effect.Tag`, `Effect.Service`      | `Context.Service<Self, Shape>()("Id")`, or `Context.Service<Self>()("Id", { make })`                                                   |
| `.Default` / `.Live` layers, `dependencies: [...]` | An explicit `static readonly layer = Layer.effect(this, this.make).pipe(Layer.provide(...))`. Use `layerTest` and similar for variants |
| Static accessor proxies (`Service.method()`)       | `yield* Service` inside `Effect.gen` / `Effect.fn`                                                                                     |
| `Effect.catchAll`, `catchAllCause`, `catchSome`    | `Effect.catch`, `Effect.catchCause`, `Effect.catchFilter`                                                                              |
| `Either`                                           | `Result` (`Result.succeed` / `Result.fail`)                                                                                            |
| `Schema.TaggedError` (v3 signature)                | `Schema.TaggedError<Self>()("Tag", { ... }, { httpApiStatus })` (the beta name `TaggedErrorClass` is gone in the RC)                   |
| `Runtime<R>`, `Runtime.runFork(runtime)`           | `Context<R>` with `Effect.runForkWith(services)`, or `ManagedRuntime` at the edge                                                      |
| `FiberRef`                                         | `Context.Reference`                                                                                                                    |
| `@effect/platform`, `@effect/rpc`                  | `effect/http`, `effect/http-api`, `effect/rpc` (the betas used `effect/unstable/*`; the RC moved them)                                 |

House style:

- Write functions that return an Effect with `Effect.fn("name")(function*() { ... })`, not with functions that return `Effect.gen`. Pass extra combinators as arguments to `Effect.fn`, not through `.pipe`.
- Fail with `return yield* new SomeError({ ... })`.
- Domain errors are `Schema.TaggedError` classes in `packages/shared` with a plain `message` from the copy module, and know nothing about HTTP. `packages/api-spec/src/errors.ts` is the one place that gives each a status and the `{ error: { code, message } }` wire shape; endpoints list those schemas as `error`. `apps/api/src/http/ErrorShape.ts` gives bad input, unknown routes and defects the same shape. Never use ad-hoc try/catch in handlers.
- Database access goes through the `Db` service: `db.use((d) => d.select()...)` for a query and `db.transaction(effect)` to run an Effect in a transaction (every `use` inside joins it).
- Every external dependency (DB, storage, email, AI, fetch) is a service with a `layer` and a `layerTest`. Tests provide test layers, not mocks of modules.
- HTTP (`effect/http`, `effect/http-api`) and other modules marked `@stability unstable` may break between minor releases. Keep that code at the edges (HTTP, client), not in domain logic.
- The web app imports Effect **Schema** only (through Standard Schema into TanStack Form) and never runs the Effect runtime in components.

## Conventions

- **TanStack first**: reach for Router, Query, Form, Pacer, Hotkeys, Virtual, AI and Devtools before any other library.
- **One schema source**: Effect Schema in `packages/shared`. Don't add zod or TypeBox.
- **Brand**: colors live in `apps/web/src/styles/tokens.css` (the only file with raw hex) and are used through `colors`, `fonts`, `type` and `quantity` in `tokens.stylex.ts`. Brand assets come from `bun run brand` (`brand/build.ts`), which writes `brand/*.svg` and the icons in `apps/web/public`. Follow issue #1 and the [brand book](https://claude.ai/artifact/G1C5x9s76ey5iEN6sbhMgu). Use Catppuccin Mocha and Latte tokens only, with no raw hex outside the token file. Set every quantity, unit, time and date in Geist Mono.
- **Copy**: every user-facing string comes from the copy module and is marked `voice` or `plain`. The rule is magic verbs with plain nouns. Errors, quantities, step controls and the literal part of delete confirmations are always plain.
- **Tables** use `timestamps()` / `timestampMs()` from `packages/db/src/schema/columns.ts` (millisecond precision, which keyset pagination relies on) and the `ownerId()` column, which cascades on user deletion.
- **Ingredients** are always stored structured (quantity, unit, item, note, original line). Never store only a free-text blob.
- **Ownership**: every owned row has `owner_id`, and every query is scoped to the current user.

## Delegation

The main session runs on **Opus at medium effort** (`.claude/settings.json`). It plans, orchestrates, reviews, and does the larger or cross-cutting work itself: architecture, anything touching several packages, Effect layer wiring, and auth. Everything else goes to the agents in `.claude/agents/`:

- `coder` (Sonnet 5.5, high): one ticket or a bounded piece of one, code and tests, in its own worktree, ending in a draft PR.
- `scout` (Haiku): read-only lookups for writing a brief.
- `adversary` (Fable): tries to break a ticket breakdown or a risky PR.
- On an agent team, `reviewer` (Sonnet 5.5, high) gives each draft PR a first pass and `shepherd` (Haiku) reruns checks and cleans up after merges.

A session spawned as one of these follows its own file instead. Opus reviews every PR before it is marked ready. When delegating a ticket, starting an agent team, stacking or merging PRs, or reviewing a coder's PR, read `docs/agents/orchestration.md`.

Subagents without a named type default to Sonnet 5.5 (`CLAUDE_CODE_SUBAGENT_MODEL`). Subagents start cold, so every brief stands alone.
