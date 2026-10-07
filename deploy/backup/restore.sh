#!/bin/sh
# Restores a snapshot (default: latest) into TARGET (default /restore): the
# database dump lands at TARGET/backup/cauldron.dump and the photos under
# TARGET/photos. With RESTORE_DATABASE_URL set, also loads the dump into that
# database, replacing what is there. Point it at a scratch database, never at
# production by accident.
#   restore.sh [snapshot-id]
set -eu

: "${RESTIC_REPOSITORY:?set RESTIC_REPOSITORY}"
: "${RESTIC_PASSWORD:?set RESTIC_PASSWORD}"
snapshot="${1:-latest}"
target="${TARGET:-/restore}"

restic restore "$snapshot" --host cauldron --target "$target"
echo "[restore] files are in $target"

if [ -n "${RESTORE_DATABASE_URL:-}" ]; then
  pg_restore --clean --if-exists --no-owner --dbname="$RESTORE_DATABASE_URL" \
    "$target${WORK_DIR:-/backup}/cauldron.dump"
  echo "[restore] database loaded"
fi
