#!/bin/sh
# Stops the API container from opening connections to private addresses or to
# the VPS itself, so a server-side fetch (recipe imports) can't be pointed at
# Openship, other containers or the cloud metadata service, even through DNS
# rebinding (security audit finding 4, #21 "Security settings"). Postgres stays
# reachable, and replies on connections others open to the API still flow.
#
# Finds containers by the srcery.cauldron.role label from deploy/compose.yaml
# and rebuilds two iptables chains from their current addresses:
#   CAULDRON-API-FWD   jumped to from DOCKER-USER (traffic to other networks)
#   CAULDRON-API-HOST  jumped to from INPUT (traffic to the host's own addresses)
# Container addresses change on every deploy, so run it after each one:
#   api-egress.sh          apply once
#   api-egress.sh watch    apply, then re-apply whenever a Cauldron container starts
#   api-egress.sh remove   take the rules out again
# CAULDRON_EGRESS_ALLOW adds "address:port" pairs the API may reach, such as an
# OpenTelemetry collector on the host (e.g. "172.17.0.1:4318").
set -eu

FWD=CAULDRON-API-FWD
HOST=CAULDRON-API-HOST
PRIVATE_RANGES="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 127.0.0.0/8"
ALLOW="${CAULDRON_EGRESS_ALLOW:-}"

log() { echo "[api-egress] $*"; }

ips_for() {
  ids=$(docker ps -q --filter "label=srcery.cauldron.role=$1")
  [ -n "$ids" ] || return 0
  # shellcheck disable=SC2086
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' $ids | tr ' ' '\n' | grep -v '^$' || true
}

ensure_chain() {
  iptables -N "$1" 2>/dev/null || true
  iptables -F "$1"
}

ensure_jump() {
  iptables -C "$1" -j "$2" 2>/dev/null || iptables -I "$1" 1 -j "$2"
}

remove() {
  for pair in "DOCKER-USER $FWD" "INPUT $HOST"; do
    set -- $pair
    while iptables -D "$1" -j "$2" 2>/dev/null; do :; done
    iptables -F "$2" 2>/dev/null || true
    iptables -X "$2" 2>/dev/null || true
  done
  log "removed"
}

apply() {
  api_ips=$(ips_for api)
  pg_ips=$(ips_for postgres)
  ensure_chain "$FWD"
  ensure_chain "$HOST"
  if [ -z "$api_ips" ]; then
    log "no running API container; chains left empty"
  fi
  for api in $api_ips; do
    for chain in "$FWD" "$HOST"; do
      iptables -A "$chain" -s "$api" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    done
    for pg in $pg_ips; do
      iptables -A "$FWD" -s "$api" -d "$pg" -p tcp --dport 5432 -j RETURN
    done
    for pair in $ALLOW; do
      addr=${pair%:*}
      port=${pair##*:}
      iptables -A "$FWD" -s "$api" -d "$addr" -p tcp --dport "$port" -j RETURN
      iptables -A "$HOST" -s "$api" -d "$addr" -p tcp --dport "$port" -j RETURN
    done
    for range in $PRIVATE_RANGES; do
      iptables -A "$FWD" -s "$api" -d "$range" -j DROP
    done
    # Anything the API sends to the host itself (any of its addresses, public
    # included) is new traffic it never needs.
    iptables -A "$HOST" -s "$api" -j DROP
  done
  ensure_jump DOCKER-USER "$FWD"
  ensure_jump INPUT "$HOST"
  log "api=$(echo $api_ips) postgres=$(echo $pg_ips)"
}

case "${1:-apply}" in
  apply) apply ;;
  remove) remove ;;
  watch)
    apply
    docker events --filter type=container --filter event=start \
      --filter label=srcery.cauldron.role --format '{{.ID}}' |
      while read -r _; do apply; done
    ;;
  *)
    echo "usage: $0 [apply|watch|remove]" >&2
    exit 2
    ;;
esac
