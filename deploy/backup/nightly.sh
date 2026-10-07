#!/bin/sh
# Runs backup.sh every day at BACKUP_AT (HH:MM, UTC, default 03:00). A failed
# run is logged and retried the next night; BACKUP_PING_URL (for example a
# healthchecks.io check) is only called on success, so a missed ping alerts.
set -eu

at="${BACKUP_AT:-03:00}"
while :; do
  now=$(date -u +%s)
  next=$(date -u -d "$at" +%s)
  if [ "$next" -le "$now" ]; then next=$((next + 86400)); fi
  echo "[backup] next run at $(date -u -d "@$next" +%Y-%m-%dT%H:%M:%SZ)"
  sleep $((next - now))
  /usr/local/bin/backup.sh || echo "[backup] run failed"
done
