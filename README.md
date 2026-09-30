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

In development the API serves interactive docs at http://localhost:3000/v1/docs and the OpenAPI document (the contract for the iOS app) at `/v1/openapi.json`. Every error response has the shape `{ "error": { "code": "...", "message": "..." } }`.

To try social sign-in without Google or Apple credentials, run a throwaway OIDC provider and point the API at it:

```bash
bun run --cwd apps/api dev:oidc
# in apps/api/.env
DEV_OAUTH_DISCOVERY_URL=http://localhost:9400/.well-known/openid-configuration
```

## Environment

API (`apps/api/.env`, see [`.env.example`](apps/api/.env.example)):

| Variable                      | Default                 | Notes                                                                |
| ----------------------------- | ----------------------- | -------------------------------------------------------------------- |
| `PORT`                        | `3001`                  |                                                                      |
| `PUBLIC_URL`                  | `http://localhost:3000` | The origin the browser sees. Auth cookies and OAuth redirects use it |
| `BETTER_AUTH_SECRET`          | (required)              | 32+ random characters: `openssl rand -base64 32`                     |
| `DATABASE_URL`                | unset                   | Postgres connection string. Unset means PGlite                       |
| `PGLITE_DATA_DIR`             | in memory               | Where PGlite keeps data                                              |
| `DEV_OAUTH_DISCOVERY_URL`     | unset                   | Enables the "dev" OIDC provider                                      |
| `API_DOCS`                    | on unless production    | Serves Scalar docs at `/v1/docs`                                     |
| `NODE_ENV`                    | `development`           | `production` turns docs off by default                               |
| `GIT_SHA`                     | unset                   | Reported by `/v1/version`                                            |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | unset                   | Exports traces and logs over OTLP/HTTP                               |

Web (production server only):

| Variable      | Default                 | Notes                                                                                  |
| ------------- | ----------------------- | -------------------------------------------------------------------------------------- |
| `PORT`        | `3000`                  |                                                                                        |
| `API_ORIGIN`  | `http://localhost:3001` | Where `/v1` is proxied to                                                              |
| `TRUST_PROXY` | `false`                 | Keep a load balancer's `X-Forwarded-For` instead of replacing it with the peer address |

## Scripts

| Command                              | What                                                             |
| ------------------------------------ | ---------------------------------------------------------------- |
| `bun run dev`                        | API and web together, with reload                                |
| `vp check`                           | Format check, lint and typecheck (`vp check --fix` to fix)       |
| `bun run typecheck`                  | `tsc` per package, including Effect language-service diagnostics |
| `bun run test`                       | Every package's tests                                            |
| `bun run build`                      | Production builds                                                |
| `bun run ready`                      | All of the above, as CI runs it                                  |
| `bun run --cwd apps/web start`       | Serve the built web app (`server.ts`)                            |
| `bun run --cwd packages/db generate` | New migration from the Drizzle schema                            |

## Containers

Each app has a Dockerfile built from the repo root, so hosting stays open ([#21](https://github.com/xchrisbailey/cauldron.srcery/issues/21)):

```bash
docker build -f apps/api/Dockerfile -t cauldron-api .
docker build -f apps/web/Dockerfile -t cauldron-web .
```
