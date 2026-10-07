#!/bin/sh
# One backup: dumps Postgres, then snapshots the dump and the photos into the
# restic repository off the VPS and prunes to BACKUP_KEEP_DAILY daily snapshots.
# Reads PG* for the database, RESTIC_* for the repository and AWS_* for an
# S3-compatible bucket. Run by nightly.sh, or by hand: `backup.sh`.
set -eu

: "${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY}"
: "${RESTIC_PASSWORD:?set RESTIC_PASSWORD}"
PHOTOS_DIR="${PHOTOS_DIR:-/photos}"
WORK_DIR="${WORK_DIR:-/backup}"
KEEP_DAILY="${BACKUP_KEEP_DAILY:-14}"

log() { echo "[backup] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

if ! restic cat config >/dev/null 2>&1; then
  log "initialising the restic repository"
  restic init
fi

mkdir -p "$WORK_DIR"
dump="$WORK_DIR/cauldron.dump"
log "dumping postgres"
pg_dump --format=custom --file="$dump.partial"
mv "$dump.partial" "$dump"

log "snapshotting the dump and $PHOTOS_DIR"
restic backup --host cauldron --tag nightly "$dump" "$PHOTOS_DIR"
rm -f "$dump"

log "keeping $KEEP_DAILY daily snapshots"
restic forget --host cauldron --tag nightly --keep-daily "$KEEP_DAILY" --prune

if [ -n "${BACKUP_PING_URL:-}" ]; then
  wget -q -O /dev/null "$BACKUP_PING_URL" || log "could not reach BACKUP_PING_URL"
fi
log "done"
