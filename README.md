# Cauldron

A personal recipe box and weekly meal planner, by srcery. The plan lives in [#2](https://github.com/xchrisbailey/cauldron.srcery/issues/2); conventions for contributors (human or agent) are in [`CLAUDE.md`](CLAUDE.md).

## Layout

| Path                | What                                                                               |
| ------------------- | ---------------------------------------------------------------------------------- |
| `apps/api`          | Effect 4 `HttpApi` on Bun under `/v1`, with Better Auth mounted on `/v1/auth/*`    |
| `apps/web`          | TanStack Start + Router + Query, styled with StyleX                                |
| `packages/api-spec` | The `HttpApi` definition (endpoints only). The web client and OpenAPI come from it |
| `packages/shared`   | Effect Schemas for the domain, shared helpers and copy                             |
| `packages/db`       | Drizzle schema and migrations                                                      |

## Setup

You need [Bun](https://bun.sh) 1.4 and [Vite+](https://viteplus.dev) (`vp`). Node 22.18+ is used by some tools.

```bash
bun install
cp apps/api/.env.example apps/api/.env   # then set BETTER_AUTH_SECRET
bun run dev
```

`bun run dev` starts the API on :3001 and the web app on http://localhost:3000. The web dev server proxies `/v1` to the API, so the browser sees one origin and auth cookies stay first-party.

Locally the API runs Postgres in-process with [PGlite](https://pglite.dev), so there's nothing else to install. Data lives in `apps/api/.data/pglite`; delete it to start over. To use a real Postgres instead, run `docker compose up -d` and set `DATABASE_URL` (see [`.env.example`](apps/api/.env.example)). Migrations run when the API boots, under an advisory lock so several instances can start at once.

In development the API serves interactive docs at http://localhost:3000/v1/docs and the OpenAPI document (the contract for the iOS app) at `/v1/openapi.json`. Both are served only when `API_DOCS` is on, which production leaves off. `/v1/health` is limited to 60 checks a minute per address, and `/v1/version` reports the commit it was built from: the repository already says what a commit contains, and it helps when checking a deploy. Every error response has the shape `{ "error": { "code": "...", "message": "..." } }`.

To try social sign-in without Google or Apple credentials, run a throwaway OIDC provider and point the API at it:

```bash
bun run --cwd apps/api dev:oidc
# in apps/api/.env
DEV_OAUTH_DISCOVERY_URL=http://localhost:9400/.well-known/openid-configuration
```

To load a demo account with a few recipes (stop the API first when using PGlite):

```bash
bun run --cwd packages/db seed   # demo@cauldron.local / cauldron-demo
SEED_COUNT=500 bun run --cwd packages/db seed   # also generate up to 500 recipes
```

## Environment

API (`apps/api/.env`, see [`.env.example`](apps/api/.env.example)):

| Variable                                                                | Default                 | Notes                                                                                                                                                                                                                              |
| ----------------------------------------------------------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PORT`                                                                  | `3001`                  |                                                                                                                                                                                                                                    |
| `PUBLIC_URL`                                                            | `http://localhost:3000` | The origin the browser sees. Auth cookies and OAuth redirects use it. Production requires an https origin with no path                                                                                                             |
| `BETTER_AUTH_SECRET`                                                    | (required)              | 32+ random characters, enforced in production. Generate with `openssl rand -base64 32`                                                                                                                                             |
| `DATABASE_URL`                                                          | unset                   | Postgres connection string. Unset means PGlite; required in production                                                                                                                                                             |
| `TRUST_PROXY`                                                           | `false`                 | Trust the web proxy's `x-client-ip` for rate limits and auth. Set it only when the API is reachable through the web proxy alone                                                                                                    |
| `SIGNUP_MODE`, `SIGNUP_ALLOWED_EMAILS`                                  | `open`                  | Who may create an account: `open`, `closed`, or `allowlist` (the comma-separated addresses in `SIGNUP_ALLOWED_EMAILS`). Covers email sign-up and a first social sign-in; existing users sign in either way. Production must set it |
| `PGLITE_DATA_DIR`                                                       | in memory               | Where PGlite keeps data                                                                                                                                                                                                            |
| `DEV_OAUTH_DISCOVERY_URL`                                               | unset                   | Enables the "dev" OIDC provider                                                                                                                                                                                                    |
| `RESEND_API_KEY`, `EMAIL_FROM`                                          | unset                   | Send email through Resend. Unset prints emails (with their links) to the API log                                                                                                                                                   |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`                              | unset                   | Sign in with Google                                                                                                                                                                                                                |
| `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET`, `APPLE_APP_BUNDLE_IDENTIFIER` | unset                   | Sign in with Apple                                                                                                                                                                                                                 |
| `API_DOCS`                                                              | on unless production    | Serves Scalar docs at `/v1/docs` and the OpenAPI document at `/v1/openapi.json`                                                                                                                                                    |
| `NODE_ENV`                                                              | `development`           | `production` turns docs off by default and requires `DATABASE_URL`, `PUBLIC_URL`, `SIGNUP_MODE` and a 32+ character secret                                                                                                         |
| `GIT_SHA`                                                               | unset                   | Reported by `/v1/version`                                                                                                                                                                                                          |
| `OTEL_EXPORTER_OTLP_ENDPOINT`                                           | unset                   | Exports traces and logs over OTLP/HTTP                                                                                                                                                                                             |

Web (production server only):

| Variable          | Default                 | Notes                                                                                                                                                              |
| ----------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `PORT`            | `3000`                  |                                                                                                                                                                    |
| `API_ORIGIN`      | `http://localhost:3001` | Where `/v1` is proxied to                                                                                                                                          |
| `TRUST_PROXY`     | `false`                 | Take the client address from the rightmost `X-Forwarded-For` entry (added by your load balancer) instead of the peer address. Sent to the API as `x-client-ip`     |
| `PUBLIC_URL`      | unset                   | The origin the browser sees. When it is `https://`, responses carry `Strict-Transport-Security`                                                                    |
| `CSP_REPORT_ONLY` | `false`                 | Sends the Content-Security-Policy as `Content-Security-Policy-Report-Only`. Use it for a first deploy and watch the browser console                                |
| `CSP_CONNECT_SRC` | unset                   | Extra origins (space or comma separated) for the policy's `connect-src` and `img-src`, such as the S3 endpoint when the browser uploads photos straight to storage |

The production server sets security headers on every response: `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Frame-Options` and, over https, HSTS. Pages also get a Content-Security-Policy that allows scripts only from the app itself, with a fresh nonce per request for the few inline ones.

## Scripts

| Command                              | What                                                             |
| ------------------------------------ | ---------------------------------------------------------------- |
| `bun run dev`                        | API and web together, with reload                                |
| `vp check`                           | Format check, lint and typecheck (`vp check --fix` to fix)       |
| `bun run typecheck`                  | `tsc` per package, including Effect language-service diagnostics |
| `bun run test`                       | Every package's tests                                            |
| `bun run build`                      | Production builds                                                |
| `bun run brand`                      | Regenerate the brand SVGs, favicon and app icons                 |
| `bun run ready`                      | All of the above, as CI runs it                                  |
| `bun run --cwd apps/web start`       | Serve the built web app (`server.ts`)                            |
| `bun run --cwd packages/db generate` | New migration from the Drizzle schema                            |

## Auth

Better Auth runs inside the API on `/v1/auth/*`. The web app uses cookie sessions (same site as the API, so they stay first-party); email and password accounts must confirm their email before signing in. `SIGNUP_MODE` decides who may create an account at all; when it is `closed` the web app hides its sign-up screens. Locally, confirmation and reset links are printed in the API log.

Every `/v1` data route goes through the `Authorization` middleware, which accepts either the session cookie or a bearer token, and rejects cookie-authenticated writes that don't come from `PUBLIC_URL` (a CSRF guard).

The iOS app, like any client without a browser, signs in with `POST /v1/auth/sign-in/email` (or the social flow) and reads the `set-auth-token` response header. It sends that token as `Authorization: Bearer <token>` on every request. Store the header value exactly as received: it is signed (`token.signature`), and a bare session token is rejected. Bearer requests skip the Origin check, and the token is the same session the cookie holds, so sign-out (`POST /v1/auth/sign-out` with the bearer header) revokes it.

## What is kept

Distill keeps the text you paste, and the readable text it pulls from a link or caption, on the import job for 7 days after the job finishes, then erases it. The job itself (its draft, link and status) is deleted after 30 days. A saved recipe keeps its own source link.

## Containers

Each app has a Dockerfile built from the repo root, so hosting stays open ([#21](https://github.com/xchrisbailey/cauldron.srcery/issues/21)):

```bash
docker build -f apps/api/Dockerfile -t cauldron-api .
docker build -f apps/web/Dockerfile -t cauldron-web .
```
