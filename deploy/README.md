# Deploying Cauldron

Production runs on the OVH VPS under [Openship](https://openship.io), as one compose stack: `postgres`, `api` and `web` ([`compose.yaml`](compose.yaml)). `openship.json` at the repo root points Openship at that file. Only `web` is public; it serves the app and proxies `/v1` to `api`, which no one else can reach.

Every push to `main` that passes CI deploys that exact commit ([`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)): GitHub Actions asks Openship to build the commit on the VPS, waits for the stack's health checks, and then checks `/v1/health` on the live site. The API runs any new migrations as it boots. A red CI run deploys nothing.

The rest of the launch checklist (security settings, backups, the smoke test) is on [#21](https://github.com/xchrisbailey/cauldron.srcery/issues/21).

## One-time setup

### 1. Openship project

1. In Openship, connect GitHub (**Settings → Git**) and create a project from `xchrisbailey/cauldron.srcery`, branch `main`, deploying to the VPS. Openship reads `openship.json` and should detect a compose project with three services. If it asks for the compose path, it is `deploy/compose.yaml`.
2. Leave **Auto-deploy** off (project **Source** tab). GitHub Actions deploys after CI instead.
3. In **Services**, mark `web` **Public** on port `3000` and attach the domain with Let's Encrypt. Keep `api` and `postgres` **Internal**. Neither should have a host port.
4. Make sure the proxy accepts request bodies of at least 20 MB, because photo uploads go through `web`.
5. If the VPS has 2 GB of RAM or less, have Openship build somewhere other than the VPS, because the web build is heavy.

### 2. Variables in Openship

Set **project** variables. Compose reads these two for its `${...}` values, and Openship hands project variables to every service:

| Variable            | Value                                                                       |
| ------------------- | --------------------------------------------------------------------------- |
| `POSTGRES_PASSWORD` | `openssl rand -hex 24` (secret). Set it once; Postgres keeps the first one. |
| `PUBLIC_URL`        | `https://<domain>`, no trailing slash                                       |

Set these on the **`api` service only**, so the web container never sees them:

| Variable                                                                | Value                                                              |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `BETTER_AUTH_SECRET`                                                    | `openssl rand -base64 32` (secret)                                 |
| `SIGNUP_MODE`, `SIGNUP_ALLOWED_EMAILS`                                  | `allowlist` and your address for the first sign-up, then `closed`  |
| `RESEND_API_KEY`, `EMAIL_FROM`                                          | Resend key (secret), and an address on a domain verified in Resend |
| `GEMINI_API_KEY`                                                        | Google AI Studio key (secret)                                      |
| `INSTAGRAM_OEMBED_TOKEN`                                                | Optional, `app-id\|client-token` (secret)                          |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`                              | Optional. Redirect URI `<PUBLIC_URL>/v1/auth/callback/google`      |
| `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET`, `APPLE_APP_BUNDLE_IDENTIFIER` | Optional. Return URL `<PUBLIC_URL>/v1/auth/callback/apple`         |
| `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`             | Optional collector (see #21)                                       |

On the **`web` service**, set `CSP_REPORT_ONLY=true` for the first deploy only (see below).

Compose already sets `NODE_ENV`, `PORT`, `DATABASE_URL`, `TRUST_PROXY`, `STORAGE_DIR` and `API_ORIGIN`. Leave `S3_BUCKET` and `API_DOCS` unset. Photos live on the `photos` volume, and API docs stay off in production.

### 3. GitHub

Create a personal access token in Openship (**Settings**), then add these under the repo's **Settings → Environments → production** (or as repo secrets):

| Name                     | Kind     | Value                                                 |
| ------------------------ | -------- | ----------------------------------------------------- |
| `OPENSHIP_TOKEN`         | secret   | The token (`opsh_pat_...`)                            |
| `OPENSHIP_API_URL`       | secret   | Openship's API URL                                    |
| `OPENSHIP_DASHBOARD_URL` | secret   | Openship's dashboard URL                              |
| `OPENSHIP_PROJECT_ID`    | secret   | The project id (`openship project list`)              |
| `PUBLIC_URL`             | variable | `https://<domain>`, used for the check after a deploy |

GitHub's runners must be able to reach the Openship API URL over https.

## First deploy

1. Run **Actions → Deploy → Run workflow** on `main`, or push to `main`.
2. Open the site with the browser console open. Sign up with the allowlisted address, confirm the email, upload a photo and open cook mode. Look for CSP reports.
3. Remove `CSP_REPORT_ONLY` from `web` and set `SIGNUP_MODE=closed` on `api`. Then run the Deploy workflow again. It redeploys the same commit with the new variables.
4. Work through the rest of #21: the network checks, backups and a restore, the smoke test and the uptime check.

## Day to day

- **Deploy:** merge to `main`. The Deploy run links to the site and fails if Openship's deploy fails or the site doesn't answer afterwards.
- **Watch a deploy:** `openship logs <deployment-id> --follow`, or the Openship dashboard.
- **Roll back:** `openship deployment rollback`, or the dashboard. Migrations only move forward. Rolling back past a migration leaves the newer schema in place, which older code usually tolerates when the migration only added things. Anything else needs a restore.
- **Change a variable:** edit it in Openship, then run the Deploy workflow by hand to apply it.

## Not here yet

- Preview environments and staging. Each would need its own database and volume. A second Openship project on the same VPS is the cheap way to add staging later.
- Error tracking (Sentry). This is a follow-up on #21.
