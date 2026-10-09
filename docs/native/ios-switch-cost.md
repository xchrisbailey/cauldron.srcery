# Cauldron as a native iOS (+ Mac) app: what it costs

Written 2026-10-09. Assumption: keep the existing Bun API and Postgres on the OVH VPS as the backend, and build a SwiftUI app against it, multiplatform for Mac.

## What there is to rebuild

Checked in the repo today:

- **12 signed-in screens** in `apps/web/src/routes/_authed` (recipes list/detail/new/edit, Distill import, Week planner, Gather list, tracker diary/check-in/weight/targets, account), the Brew cooking mode, and 4 auth screens. About 16.5k lines of web TypeScript.
- **~53 API endpoints** in `packages/api-spec` (Recipes 12, Tracker 17, Plan 7, Photos 5, Imports 4, Gather 4, plus auth/meta).
- The API already speaks to a native client: bearer tokens are accepted without cookies (`apps/api/src/http/Authorization.ts`), and Sign in with Apple takes an app bundle id (`APPLE_APP_BUNDLE_IDENTIFIER` in `apps/api/src/AppConfig.ts`). The OpenAPI spec was designed as the iOS contract (#22), so a Swift client can be generated with Apple's `swift-openapi-generator`.

What does **not** carry over is the shared TypeScript the web runs client-side: the ingredient line parser, unit scaling, the copy module, brewing timers and plan macro maths in `packages/shared`. Each piece either moves behind an endpoint (parser, macro maths) or gets ported to Swift (scaling, timers, copy strings). Brand tokens need a Swift version (Catppuccin colours, Geist + Geist Mono bundled).

## Effort

| Piece | Size |
| --- | --- |
| Project setup, generated API client, auth (email, Apple, Google) and Keychain session | small–medium |
| Recipes: list, detail, editor with structured ingredients, photos (PhotosPicker + upload) | medium |
| Distill imports, plus a Share Extension so you can share a URL or caption from Safari/Instagram straight in | medium (the share sheet is the big native win) |
| Week planner + Gather list | medium |
| Tracker: diary, describe-it, log recipe, recents, weigh-ins, targets | medium–large (largest surface) |
| Brew mode (keep screen awake, timers, Live Activity optional) | small–medium |
| HealthKit (weight in, nutrition out), deferred until now | small–medium |
| Mac via SwiftUI multiplatform | +20–30% on top, mostly layout and menus |

At the pace the web phases shipped (agent-built, you reviewing), a usable iPhone app is roughly the size of two or three of the web phases, not a restart. The backend needs only small additions (moving client-side logic behind endpoints, an account-deletion endpoint if not already reachable from the app, push later if wanted).

Practical constraint: Swift builds, simulators and signing need macOS and Xcode, so the cloud threads can write Swift but can't compile or run it. The build/test loop runs through Remote Control on your Mac (or Xcode Cloud).

## Money

| Item | Cost |
| --- | --- |
| Apple Developer Program (needed for TestFlight, App Store, Sign in with Apple, HealthKit, CloudKit) | $99/year |
| Hosting | unchanged: same VPS, same API, web can stay as is or be frozen |
| AI (Gemini) | unchanged, as long as model calls stay on the API. Keys must never ship in the app, so they stay server-side either way |
| CI | Xcode Cloud includes 25 compute hours/month with the membership, enough for this. GitHub Actions macOS runners count at 10x minutes on private repos, so avoid them for routine builds |
| Fonts | Geist is OFL, free to bundle |

So the real-money delta is **$99/year**. The real cost is build time and keeping two clients in step if the web stays alive.

## App Store points to plan for

- Offering Google sign-in means Sign in with Apple must be offered too (already planned).
- Accounts created in the app must be deletable from inside the app.
- Signup is currently allowlist/closed in prod (`SIGNUP_MODE`); for TestFlight that's fine, for public App Store review Apple needs a demo account.

## Alternative: local-first with SwiftData + CloudKit

Data lives on device and syncs through your iCloud, no server or Postgres needed for storage, free sync. But:

- The AI features (Distill, describe-it, divine macros) and URL/Instagram fetching still need a server, because API keys can't live in the app. So the VPS doesn't go away, it just shrinks to a stateless AI/import proxy.
- The web app and the Postgres data model are dropped, and data would need migrating once.
- Households (#24) and sharing get harder (CloudKit sharing works but is fiddly).
- It's a bigger rewrite: domain logic moves into Swift instead of being called over HTTP.

Worth it only if you want to retire the backend and web entirely. Otherwise keep the API.

## Recommendation

Keep the API and Postgres, build a SwiftUI multiplatform app on the generated OpenAPI client, and freeze the web app (leave it deployed, stop adding features). Start with recipes + Distill via the share sheet, then tracker + HealthKit, then planner/Gather, then the Mac layout.

## Follow-up (2026-10-09): no API at all, Apple on-device AI + phone storage

Feasible. What replaces each server piece:

| Today (server) | Phone-only replacement | Catch |
| --- | --- | --- |
| Postgres + Drizzle | SwiftData, synced iPhone↔Mac through CloudKit's private database | Free to you; photos count against your own iCloud storage. Sharing/households (#24) needs CKShare, which is fiddly |
| Better Auth (email, Google, Apple) | Nothing: the iCloud account is the identity | No sign-in screens at all |
| Gemini via TanStack AI | Apple Foundation Models framework (on-device model, structured output via `@Generable`) | Needs an Apple Intelligence device (iPhone 15 Pro or newer, M-series Mac). Small model with a short context window (~4k tokens), so long recipe pages need trimming first, and "describe it" macro estimates will be less accurate than Gemini because that leans on food knowledge a small model lacks |
| URL fetching for imports | URLSession on the phone | Sites that block servers (Allrecipes, Serious Eats) may well work from a phone |
| Instagram oEmbed (app token) | Share sheet hands the caption text in directly | Token can't ship in an app; share sheet avoids needing it |
| Parser, scaling, macro calculator, adaptive targets | Ported to Swift | Deterministic code, straightforward port with tests |

Money: $99/year, and Cauldron no longer needs the VPS, Postgres, backups, deploy pipeline or Gemini key. The web app goes away.

Biggest risk is AI quality, mainly macro estimates. A middle path if it disappoints: stay phone-only for data, and call Gemini directly only for "describe it"/"divine macros". That needs a key, which can't safely live in the app, so it would mean a tiny stateless proxy, which is the one thing that brings a server back.

### Update: iOS 27 Private Cloud Compute model

iOS 27's Foundation Models framework lets apps use Apple's server model as well, through `PrivateCloudComputeLanguageModel.default` in place of the on-device model. Prompts, `@Generable` output and tools work the same way. It has a 32K-token context (the on-device model has 4K) and three reasoning levels. There are no API keys and no token cost for apps under 2M first-time downloads, but the app needs an entitlement you apply for. Each user gets a daily request quota tied to their iCloud account, larger with iCloud+. It needs a network connection and an Apple Intelligence device. Sources: blakecrosley.com/blog/foundation-models-private-cloud-compute, creuto.com/foundation-models-framework-ios-27-apps.

Effect on the plan: Distill (long pages) and describe-it/divine macros go to PCC, and quick structured tasks stay on-device. This removes the main reason to keep a Gemini proxy, so the phone-only design needs no server at all.
