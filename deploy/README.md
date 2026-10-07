# Deploying Cauldron

Production runs on the OVH VPS under [Openship](https://openship.io), as one compose stack: `postgres`, `api`, `web` and `backup` ([`compose.yaml`](compose.yaml)). `openship.json` at the repo root points Openship at that file. Only `web` is public; it serves the app and proxies `/v1` to `api`, which no one else can reach. Only `api` and `backup` can reach `postgres`.

Every push to `main` that passes CI deploys that exact commit ([`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)): GitHub Actions asks Openship to build the commit on the VPS, waits for the stack's health checks, and then checks `/v1/health` on the live site. The API runs any new migrations as it boots. A red CI run deploys nothing.

The rest of the launch checklist (security settings, backups, the smoke test) is on [#21](https://github.com/xchrisbailey/cauldron.srcery/issues/21).

## One-time setup

### 1. Openship project

1. In Openship, connect GitHub (**Settings → Git**) and create a project from `xchrisbailey/cauldron.srcery`, branch `main`, deploying to the VPS. Openship reads `openship.json` and should detect a compose project with the services in `compose.yaml`. If it asks for the compose path, it is `deploy/compose.yaml`.
2. Leave **Auto-deploy** off (project **Source** tab). GitHub Actions deploys after CI instead.
3. In **Services**, mark `web` **Public** on port `3000` and attach the domain with Let's Encrypt. Keep every other service **Internal**, with no host port. Check that Openship kept the compose file's `networks` (postgres is only on `data`, web only on `default`).
4. Make sure the proxy accepts request bodies of at least 20 MB, because photo uploads go through `web`.
5. If the VPS has 2 GB of RAM or less, have Openship build somewhere other than the VPS, because the web build is heavy.

### 2. Variables in Openship

Generate the database password once with `openssl rand -hex 24`. Postgres keeps the password it was first started with, so don't change it later without also changing it inside the database.

Set one **project** variable. Compose interpolates it, and it isn't secret:

| Variable     | Value                                 |
| ------------ | ------------------------------------- |
| `PUBLIC_URL` | `https://<domain>`, no trailing slash |

Set **service** variables so each container gets only its own secrets. On **`postgres`**:

| Variable            | Value                          |
| ------------------- | ------------------------------ |
| `POSTGRES_PASSWORD` | The database password (secret) |

Set these on the **`api` service only**, so the web container never sees them:

| Variable                                                                | Value                                                                     |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `DATABASE_URL`                                                          | `postgres://cauldron:<database password>@postgres:5432/cauldron` (secret) |
| `BETTER_AUTH_SECRET`                                                    | `openssl rand -base64 32` (secret)                                        |
| `SIGNUP_MODE`, `SIGNUP_ALLOWED_EMAILS`                                  | `allowlist` and your address for the first sign-up, then `closed`         |
| `RESEND_API_KEY`, `EMAIL_FROM`                                          | Resend key (secret), and an address on a domain verified in Resend        |
| `GEMINI_API_KEY`                                                        | Google AI Studio key (secret)                                             |
| `INSTAGRAM_OEMBED_TOKEN`                                                | Optional, `app-id\|client-token` (secret)                                 |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`                              | Optional. Redirect URI `<PUBLIC_URL>/v1/auth/callback/google`             |
| `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET`, `APPLE_APP_BUNDLE_IDENTIFIER` | Optional. Return URL `<PUBLIC_URL>/v1/auth/callback/apple`                |
| `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`             | Optional collector (see #21)                                              |

On the **`web` service**, set `CSP_REPORT_ONLY=true` for the first deploy only (see below). Then open its **Environment** view and check that none of the secrets above are listed there.

Compose already sets `NODE_ENV`, `PORT`, `TRUST_PROXY`, `STORAGE_DIR` and `API_ORIGIN`. Leave `S3_BUCKET` and `API_DOCS` unset. Photos live on the `photos` volume, and API docs stay off in production.

Set these on the **`backup` service** (see [Backups](#backups)):

| Variable                                     | Value                                                                                                  |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `PGPASSWORD`                                 | The database password (secret)                                                                         |
| `RESTIC_REPOSITORY`                          | `s3:https://<endpoint>/<bucket>`, a bucket **off the VPS** (R2, OVH Object Storage, Backblaze B2)      |
| `RESTIC_PASSWORD`                            | `openssl rand -base64 32` (secret). Keep a copy outside the VPS: without it the backups are unreadable |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | A key that can only read and write that bucket (secret)                                                |
| `BACKUP_AT`, `BACKUP_KEEP_DAILY`             | Optional. UTC time of the nightly run (default `03:00`) and days kept (default `14`)                   |
| `BACKUP_PING_URL`                            | Optional. Called after each successful run, e.g. a healthchecks.io check that alerts on a miss         |

### 3. GitHub

Create a personal access token in Openship (**Settings**). Add the secrets below under the repo's **Settings → Environments → production** (or as repo secrets). `PUBLIC_URL` must be a **repository** variable (**Settings → Secrets and variables → Actions → Variables**), because the workflow checks it before the environment loads:

| Name                     | Kind     | Value                                                                                      |
| ------------------------ | -------- | ------------------------------------------------------------------------------------------ |
| `OPENSHIP_TOKEN`         | secret   | The token (`opsh_pat_...`)                                                                 |
| `OPENSHIP_API_URL`       | secret   | Openship's API URL                                                                         |
| `OPENSHIP_DASHBOARD_URL` | secret   | Openship's dashboard URL                                                                   |
| `OPENSHIP_PROJECT_ID`    | secret   | The project id (`openship project list`)                                                   |
| `PUBLIC_URL`             | variable | `https://<domain>`, used for the check after a deploy. Deploys are skipped until it is set |

GitHub's runners must be able to reach the Openship API URL over https.

## First deploy

1. Run **Actions → Deploy → Run workflow** on `main`, or push to `main`.
2. Open the site with the browser console open. Sign up with the allowlisted address, confirm the email, upload a photo and open cook mode. Look for CSP reports.
3. Remove `CSP_REPORT_ONLY` from `web` and set `SIGNUP_MODE=closed` on `api`. Then run the Deploy workflow again. It redeploys the same commit with the new variables.
4. Work through the rest of #21: the network checks, backups and a restore, the smoke test and the uptime check.

## Day to day

- **Deploy:** merge to `main`. The Deploy run links to the site and fails if Openship's deploy fails or the site doesn't answer afterwards. A run for a commit that is no longer the tip of `main` (a re-run of an old CI run) deploys nothing, so it can't roll production back by accident.
- **Watch a deploy:** `openship logs <deployment-id> --follow`, or the Openship dashboard.
- **Roll back:** `openship deployment rollback`, or the dashboard. Migrations only move forward. Rolling back past a migration leaves the newer schema in place, which older code usually tolerates when the migration only added things. Anything else needs a restore.
- **Change a variable:** edit it in Openship, then run the Deploy workflow by hand to apply it. A manual run deploys the tip of `main`, and only if CI passed on it.

## Backups

The `backup` service runs [`backup/backup.sh`](backup/backup.sh) every night. It takes a `pg_dump` of the database, then has [restic](https://restic.net) snapshot the dump and the `photos` volume (mounted read-only) into the bucket. Snapshots are encrypted with `RESTIC_PASSWORD` and deduplicated, so a night with no new photos adds little. Only the last `BACKUP_KEEP_DAILY` days are kept. The first run creates the repository.

- **Back up now:** run `backup.sh` in the `backup` container, from Openship's service shell or `docker exec <backup-container> backup.sh` on the VPS.
- **List snapshots:** `restic snapshots` in the same container.
- **Restore drill** (#21 asks for one): on another machine, with the same `RESTIC_*` and `AWS_*` values exported in your shell, run the image against a scratch Postgres:

  ```sh
  docker build -t cauldron-backup deploy/backup
  docker run --rm --network host \
    -e RESTIC_REPOSITORY -e RESTIC_PASSWORD -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
    -e RESTORE_DATABASE_URL=postgres://user:pass@127.0.0.1:5432/scratch \
    -v "$PWD/restore:/restore" cauldron-backup restore.sh
  ```

  `--network host` lets the container reach a Postgres on your machine. That loads the dump into the scratch database and puts the photos in `restore/photos/storage`. Point a local API at both (`DATABASE_URL` and `STORAGE_DIR=$PWD/restore/photos/storage`) and sign in. Pass a snapshot id to `restore.sh` to restore an older night. The load runs in one transaction, so a failed restore leaves the database as it was.

- **Restore production:** stop `api` and `backup` in Openship. Then run two one-off containers on the VPS from the backup image. The volume and network names carry Openship's project prefix, which `docker volume ls` and `docker network ls` show.

  ```sh
  # 1. Fetch the snapshot (needs the internet, so the default network) and put the photos back.
  docker run --rm -e RESTIC_REPOSITORY -e RESTIC_PASSWORD -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
    -v /root/cauldron-restore:/restore -v <project>_photos:/photos-live <backup-image> \
    sh -c 'restore.sh && rm -rf /photos-live/storage && cp -a /restore/photos/storage /photos-live/ && chown -R 1000:1000 /photos-live/storage'
  # 2. Load the dump into production Postgres, in one transaction.
  docker run --rm --network <project>_data -e PGPASSWORD -v /root/cauldron-restore:/restore <backup-image> \
    pg_restore --clean --if-exists --no-owner --single-transaction --exit-on-error \
    -h postgres -U cauldron -d cauldron /restore/backup/cauldron.dump
  ```

  Then start `api` and `backup` again and delete `/root/cauldron-restore`. The `chown` is there because the API runs as `bun` (uid 1000).

## Not here yet

- Preview environments and staging. Each would need its own database and volume. A second Openship project on the same VPS is the cheap way to add staging later.
- Error tracking (Sentry). This is a follow-up on #21.
