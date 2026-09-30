# Cauldron

A personal recipe box and weekly meal planner, by srcery. The web app comes first, followed by an iOS app and macro tracking. The plan lives in the v1 epic, [#2](https://github.com/xchrisbailey/cauldron.srcery/issues/2). Every ticket is a sub-issue of it and says what it depends on and when it's done.

## Stack

- **Monorepo**: Vite+ (`vp`) on Bun. It provides dev, build, Vitest, Oxlint, format and the task runner.
- **API** (`apps/api`): Effect 4 `HttpApi` on Bun (`@effect/platform-bun` `BunHttpServer`) under `/v1`. Postgres through Drizzle, wrapped as an Effect service.
- **API definition** (`packages/api-spec`): endpoints and groups only, with no handlers. The web app imports it to build a typed `HttpApiClient`, and the OpenAPI spec (the future iOS contract) is generated from it.
- **Shared** (`packages/shared`): Effect Schemas for the domain, the ingredient line parser, units and scaling, and the copy module.
- **DB** (`packages/db`): Drizzle schema, migrations and seed.
- **Web** (`apps/web`): TanStack Start + Router + Query, styled with StyleX using the brand tokens.
- **Auth**: Better Auth, mounted on `/v1/auth/*` through `HttpEffect.fromWebHandler`. Sessions reach handlers through an `HttpApiMiddleware` that provides `CurrentUser`.
- **AI**: TanStack AI, called from the API and wrapped as an Effect service (`RecipeExtractor`).

## Build order

Follow the "Depends on" line at the top of each ticket. The critical path:

1. **Spike first.** Before building #3 out, open one PR that proves the risky combination together: the Vite+ workspace, Effect HttpApi on Bun, the Better Auth bridge (including an OAuth callback), and a TanStack Start page styled with StyleX tokens that calls the API through `HttpApiClient` while signed in. If any piece fights back, stop and raise it on the epic before going further.
2. #3 scaffold, then #4 API foundation.
3. #5 auth and #6 data model, in parallel.
4. #1 brand tokens and assets must land before #7 web shell.
5. Phase 2 (#8 to #12), then Phase 3 imports (#13 first), then Phase 4 (#18 to #20). #21 deploy waits for the hosting decision.

The ingredient line parser in #6 feeds the editor, every importer and the Gather list. Give it its test corpus early and keep it strict.

## Effect 4 (release candidate)

The `effect` version is pinned **exactly**. Upgrade on purpose, in its own PR. Most of what you remember about Effect is v3, and v4 renamed a lot. **Check v4 sources before writing Effect code**:

- Guide for writing v4 code: https://github.com/Effect-TS/effect-smol/blob/main/LLMS.md, with runnable examples in `ai-docs/src/` (HTTP server, HTTP client, AI, testing).
- Migration notes: https://github.com/Effect-TS/effect-smol/tree/main/migration (start with `v3-to-v4.md` and `services.md`).
- When in doubt, read the source under `node_modules/effect/src` for the pinned version, and don't write it from memory.

The v3 habits that break most often:

| v3 | v4 |
|---|---|
| `Context.Tag`, `Effect.Tag`, `Effect.Service` | `Context.Service<Self, Shape>()("Id")`, or `Context.Service<Self>()("Id", { make })` |
| `.Default` / `.Live` layers, `dependencies: [...]` | An explicit `static readonly layer = Layer.effect(this, this.make).pipe(Layer.provide(...))`. Use `layerTest` and similar for variants |
| Static accessor proxies (`Service.method()`) | `yield* Service` inside `Effect.gen` / `Effect.fn` |
| `Effect.catchAll`, `catchAllCause`, `catchSome` | `Effect.catch`, `Effect.catchCause`, `Effect.catchFilter` |
| `Either` | `Result` (`Result.succeed` / `Result.fail`) |
| `Schema.TaggedError` | `Schema.TaggedErrorClass<Self>()("Tag", { ... })` |
| `Runtime<R>`, `Runtime.runFork(runtime)` | `Context<R>` with `Effect.runForkWith(services)`, or `ManagedRuntime` at the edge |
| `FiberRef` | `Context.Reference` |
| `@effect/platform`, `@effect/rpc` | `effect/unstable/http`, `effect/unstable/httpapi`, `effect/unstable/rpc` |

House style:

- Write functions that return an Effect with `Effect.fn("name")(function*() { ... })`, not with functions that return `Effect.gen`. Pass extra combinators as arguments to `Effect.fn`, not through `.pipe`.
- Fail with `return yield* new SomeError({ ... })`.
- Domain errors are `Schema.TaggedErrorClass`es in `packages/shared`. They are mapped to HTTP status and `{ error: { code, message } }` in one place in the API, and never with ad-hoc try/catch in handlers.
- Every external dependency (DB, storage, email, AI, fetch) is a service with a `layer` and a `layerTest`. Tests provide test layers, not mocks of modules.
- Anything under `effect/unstable/*` may break between RCs. Keep that code at the edges (HTTP, client), not in domain logic.
- The web app imports Effect **Schema** only (through Standard Schema into TanStack Form) and never runs the Effect runtime in components.

## Conventions

- **TanStack first**: reach for Router, Query, Form, Pacer, Hotkeys, Virtual, AI and Devtools before any other library.
- **One schema source**: Effect Schema in `packages/shared`. Don't add zod or TypeBox.
- **Brand**: follow issue #1 and the [brand book](https://claude.ai/artifact/G1C5x9s76ey5iEN6sbhMgu). Use Catppuccin Mocha and Latte tokens only, with no raw hex outside the token file. Set every quantity, unit, time and date in Geist Mono.
- **Copy**: every user-facing string comes from the copy module and is marked `voice` or `plain`. The rule is magic verbs with plain nouns. Errors, quantities, step controls and the literal part of delete confirmations are always plain.
- **Ingredients** are always stored structured (quantity, unit, item, note, original line). Never store only a free-text blob.
- **Ownership**: every owned row has `owner_id`, and every query is scoped to the current user.

## Delegation

The main session runs on **Opus at medium effort** (`.claude/settings.json`). It plans, orchestrates, reviews, and does the larger or cross-cutting work itself: architecture, anything touching several packages, Effect layer wiring, and auth.

Small, well-defined tasks go to **Sonnet 5.5** subagents in `.claude/agents/`:

- `implementer`: one focused change with a clear spec (a route, a component, a schema, a migration, a bug fix).
- `test-writer`: tests for existing code (unit, integration, fixture corpora).

Before merging, send any non-trivial diff to `reviewer` (Opus, medium effort, read-only).

Subagents without a named type also default to Sonnet 5.5 (`CLAUDE_CODE_SUBAGENT_MODEL`). When you delegate, pass the ticket number, the exact files or area, the acceptance criteria, and the house rules above. Subagents start cold.
