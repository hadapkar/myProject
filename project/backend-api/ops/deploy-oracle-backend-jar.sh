#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo bash ops/deploy-oracle-backend-jar.sh /path/to/backend-api.jar" >&2
  exit 1
fi

INCOMING_JAR="${1:-/tmp/backend-api.jar}"
SERVICE="${KINGMAKER_BACKEND_SERVICE:-kingmaker-backend}"
APP_DIR="${KINGMAKER_BACKEND_DIR:-/opt/kingmaker/backend-api}"
JAR_PATH="${KINGMAKER_BACKEND_JAR:-$APP_DIR/build/libs/backend-api-0.0.1-SNAPSHOT.jar}"
PREVIOUS_JAR="${KINGMAKER_BACKEND_PREVIOUS_JAR:-$JAR_PATH.previous}"
BACKUP_DIR="${KINGMAKER_BACKEND_BACKUP_DIR:-$APP_DIR/build/backups}"
JAR_OWNER="${KINGMAKER_BACKEND_OWNER:-opc}"
JAR_GROUP="${KINGMAKER_BACKEND_GROUP:-opc}"
JAR_TOOL="${KINGMAKER_JAR_TOOL:-/opt/kingmaker/jdk-21/bin/jar}"
READY_URLS="${KINGMAKER_BACKEND_READY_URLS:-http://127.0.0.1:8080/readyz http://127.0.0.1/readyz}"
READY_ATTEMPTS="${KINGMAKER_BACKEND_READY_ATTEMPTS:-75}"
READY_SLEEP_SECONDS="${KINGMAKER_BACKEND_READY_SLEEP_SECONDS:-2}"

case "$READY_ATTEMPTS" in ''|*[!0-9]*) READY_ATTEMPTS=75 ;; esac
case "$READY_SLEEP_SECONDS" in ''|*[!0-9]*) READY_SLEEP_SECONDS=2 ;; esac

if [ ! -f "$INCOMING_JAR" ]; then
  echo "Incoming jar not found: $INCOMING_JAR" >&2
  exit 1
fi

if [ -x "$JAR_TOOL" ]; then
  "$JAR_TOOL" tf "$INCOMING_JAR" >/dev/null
else
  echo "Warning: jar tool not executable at $JAR_TOOL; skipping jar structure validation" >&2
fi

mkdir -p "$(dirname "$JAR_PATH")" "$BACKUP_DIR"

if [ -f "$JAR_PATH" ]; then
  cp -f "$JAR_PATH" "$PREVIOUS_JAR"
  cp -f "$JAR_PATH" "$BACKUP_DIR/backend-api-$(date +%Y%m%d%H%M%S).jar"
fi

install -m 0644 -o "$JAR_OWNER" -g "$JAR_GROUP" "$INCOMING_JAR" "$JAR_PATH"

wait_ready() {
  local attempt url
  for attempt in $(seq 1 "$READY_ATTEMPTS"); do
    for url in $READY_URLS; do
      if curl -fsS --max-time 8 "$url" >/dev/null; then
        echo "Ready: $url"
        return 0
      fi
    done
    sleep "$READY_SLEEP_SECONDS"
  done
  return 1
}

echo "Restarting $SERVICE with new jar..."
systemctl restart "$SERVICE"

if wait_ready; then
  systemctl is-active "$SERVICE"
  echo "Backend deploy completed."
  exit 0
fi

echo "New jar failed readiness. Rolling back to previous jar..." >&2
if [ ! -f "$PREVIOUS_JAR" ]; then
  echo "Rollback failed: previous jar missing at $PREVIOUS_JAR" >&2
  systemctl status "$SERVICE" --no-pager -l | sed -n '1,80p' >&2 || true
  exit 1
fi

install -m 0644 -o "$JAR_OWNER" -g "$JAR_GROUP" "$PREVIOUS_JAR" "$JAR_PATH"
systemctl restart "$SERVICE"

if wait_ready; then
  echo "Rollback completed; previous jar is active." >&2
  exit 1
fi

echo "Rollback jar also failed readiness." >&2
systemctl status "$SERVICE" --no-pager -l | sed -n '1,120p' >&2 || true
exit 1