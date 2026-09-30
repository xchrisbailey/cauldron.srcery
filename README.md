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

Locally the API runs Postgres in-process with [PGlite](https://pglite.dev), so there's nothing else to install. Data lives in `apps/api/.data/pglite`; delete it to start over.

To try social sign-in without Google or Apple credentials, run a throwaway OIDC provider and point the API at it:

```bash
bun run --cwd apps/api dev:oidc
# in apps/api/.env
DEV_OAUTH_DISCOVERY_URL=http://localhost:9400/.well-known/openid-configuration
```

## Environment

API (`apps/api/.env`, see [`.env.example`](apps/api/.env.example)):

| Variable                  | Default                 | Notes                                                                |
| ------------------------- | ----------------------- | -------------------------------------------------------------------- |
| `PORT`                    | `3001`                  |                                                                      |
| `PUBLIC_URL`              | `http://localhost:3000` | The origin the browser sees. Auth cookies and OAuth redirects use it |
| `BETTER_AUTH_SECRET`      | (required)              | 32+ random characters: `openssl rand -base64 32`                     |
| `PGLITE_DATA_DIR`         | in memory               | Where PGlite keeps data                                              |
| `DEV_OAUTH_DISCOVERY_URL` | unset                   | Enables the "dev" OIDC provider                                      |

Web (production server only):

| Variable     | Default                 | Notes                     |
| ------------ | ----------------------- | ------------------------- |
| `PORT`       | `3000`                  |                           |
| `API_ORIGIN` | `http://localhost:3001` | Where `/v1` is proxied to |

## Scripts

| Command                        | What                                                       |
| ------------------------------ | ---------------------------------------------------------- |
| `bun run dev`                  | API and web together, with reload                          |
| `vp check`                     | Format check, lint and typecheck (`vp check --fix` to fix) |
| `bun run test`                 | Every package's tests                                      |
| `bun run build`                | Production builds                                          |
| `bun run ready`                | All of the above, as CI runs it                            |
| `bun run --cwd apps/web start` | Serve the built web app (`server.ts`)                      |
| `bunx drizzle-kit generate`    | New migration from the schema (run in `packages/db`)       |

## Containers

Each app has a Dockerfile built from the repo root, so hosting stays open ([#21](https://github.com/xchrisbailey/cauldron.srcery/issues/21)):

```bash
docker build -f apps/api/Dockerfile -t cauldron-api .
docker build -f apps/web/Dockerfile -t cauldron-web .
```
