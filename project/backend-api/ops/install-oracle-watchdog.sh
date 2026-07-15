#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo bash project/backend-api/ops/install-oracle-watchdog.sh" >&2
  exit 1
fi

cat >/usr/local/bin/kingmaker-backend-watchdog <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

SERVICE="kingmaker-backend"
HEALTH_URL="${KINGMAKER_BACKEND_HEALTH_URL:-http://127.0.0.1:8080/healthz}"
STATE_DIR="/run/kingmaker-backend-watchdog"
FAIL_FILE="$STATE_DIR/failures"
MAX_FAILURES="${KINGMAKER_BACKEND_WATCHDOG_MAX_FAILURES:-3}"
STARTUP_GRACE_SECONDS="${KINGMAKER_BACKEND_STARTUP_GRACE_SECONDS:-120}"

case "$MAX_FAILURES" in ''|*[!0-9]*) MAX_FAILURES=3 ;; esac
case "$STARTUP_GRACE_SECONDS" in ''|*[!0-9]*) STARTUP_GRACE_SECONDS=120 ;; esac

mkdir -p "$STATE_DIR"

if ! systemctl is-active --quiet "$SERVICE"; then
  echo 0 >"$FAIL_FILE"
  exit 0
fi

main_pid="$(systemctl show -p MainPID --value "$SERVICE" 2>/dev/null || echo 0)"
if [[ "$main_pid" =~ ^[0-9]+$ ]] && [ "$main_pid" -gt 1 ] && [ -d "/proc/$main_pid" ]; then
  elapsed="$(ps -o etimes= -p "$main_pid" 2>/dev/null | tr -d ' ' || echo 0)"
  case "$elapsed" in ''|*[!0-9]*) elapsed=0 ;; esac
  if [ "$elapsed" -lt "$STARTUP_GRACE_SECONDS" ]; then
    echo 0 >"$FAIL_FILE"
    exit 0
  fi
fi

if curl --max-time 5 --connect-timeout 2 -fsS "$HEALTH_URL" >/dev/null; then
  echo 0 >"$FAIL_FILE"
  exit 0
fi

failures=0
if [ -f "$FAIL_FILE" ]; then
  failures="$(cat "$FAIL_FILE" 2>/dev/null || echo 0)"
fi
case "$failures" in ''|*[!0-9]*) failures=0 ;; esac
failures=$((failures + 1))
echo "$failures" >"$FAIL_FILE"

logger -t kingmaker-backend-watchdog "health check failed ($failures/$MAX_FAILURES)"

if [ "$failures" -ge "$MAX_FAILURES" ]; then
  logger -t kingmaker-backend-watchdog "restarting $SERVICE after repeated health failures"
  systemctl restart "$SERVICE"
  echo 0 >"$FAIL_FILE"
fi
SCRIPT
chmod 0755 /usr/local/bin/kingmaker-backend-watchdog

set_journal_setting() {
  local key="$1"
  local value="$2"
  local file="/etc/systemd/journald.conf"

  if grep -Eq "^[#[:space:]]*${key}=" "$file"; then
    sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

mkdir -p /var/log/journal
set_journal_setting Storage persistent
set_journal_setting SystemMaxUse 100M
set_journal_setting RuntimeMaxUse 50M
set_journal_setting MaxRetentionSec 14day
systemctl restart systemd-journald || true
journalctl --flush || true

mkdir -p /etc/systemd/system/kingmaker-backend.service.d
cat >/etc/systemd/system/kingmaker-backend.service.d/override.conf <<'UNIT'
[Service]
Restart=always
RestartSec=5s
TimeoutStartSec=90s
TimeoutStopSec=45s
KillMode=mixed
StartLimitIntervalSec=300
StartLimitBurst=10
MemoryAccounting=true
MemoryHigh=380M
MemoryMax=430M
TasksMax=160
LimitNOFILE=4096
Environment=MALLOC_ARENA_MAX=2
Environment=JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=55 -XX:InitialRAMPercentage=20 -XX:MaxMetaspaceSize=128m -XX:+UseSerialGC -XX:ActiveProcessorCount=1 -Djava.security.egd=file:/dev/urandom
UNIT

cat >/etc/systemd/system/kingmaker-backend-watchdog.service <<'UNIT'
[Unit]
Description=Kingmaker backend health watchdog
After=network-online.target kingmaker-backend.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kingmaker-backend-watchdog
UNIT

cat >/etc/systemd/system/kingmaker-backend-watchdog.timer <<'UNIT'
[Unit]
Description=Run Kingmaker backend health watchdog every 30 seconds

[Timer]
OnBootSec=120s
OnUnitActiveSec=30s
AccuracySec=10s
Unit=kingmaker-backend-watchdog.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now kingmaker-backend.service
systemctl enable --now kingmaker-backend-watchdog.timer
systemctl restart kingmaker-backend.service
systemctl status kingmaker-backend.service --no-pager -l | sed -n '1,25p'
systemctl list-timers kingmaker-backend-watchdog.timer --no-pager
