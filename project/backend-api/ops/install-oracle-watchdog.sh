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

ensure_swap() {
  local swapfile="${KINGMAKER_SWAPFILE:-/swapfile}"
  local swap_mb="${KINGMAKER_SWAP_MB:-1536}"

  case "$swap_mb" in ''|*[!0-9]*) swap_mb=1536 ;; esac

  if swapon --show=NAME --noheadings | grep -q .; then
    return 0
  fi

  if [ ! -f "$swapfile" ]; then
    fallocate -l "${swap_mb}M" "$swapfile" || dd if=/dev/zero of="$swapfile" bs=1M count="$swap_mb" status=progress
    chmod 0600 "$swapfile"
    mkswap "$swapfile"
  fi

  if ! grep -Eq "^[^#].*[[:space:]]swap[[:space:]]" /etc/fstab; then
    printf '%s none swap sw 0 0\n' "$swapfile" >>/etc/fstab
  fi

  swapon "$swapfile" || true
}
mkdir -p /var/log/journal
set_journal_setting Storage persistent
set_journal_setting SystemMaxUse 100M
set_journal_setting RuntimeMaxUse 50M
set_journal_setting MaxRetentionSec 14day
systemctl restart systemd-journald || true
journalctl --flush || true

ensure_swap

cat >/etc/sysctl.d/99-kingmaker-tiny-vm.conf <<'SYSCTL'
vm.swappiness=20
vm.vfs_cache_pressure=50
vm.min_free_kbytes=65536
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=300
net.core.somaxconn=256
SYSCTL
sysctl --system >/dev/null || true

# The 1 GB Oracle micro VM can freeze when background maintenance jobs spike memory.
# Keep package/search/kernel patch refresh manual and intentional.
systemctl disable --now dnf-makecache.timer >/dev/null 2>&1 || true
systemctl stop dnf-makecache.service >/dev/null 2>&1 || true
systemctl disable --now mlocate-updatedb.timer >/dev/null 2>&1 || true
systemctl stop mlocate-updatedb.service >/dev/null 2>&1 || true
systemctl disable --now ksplice-agent.timer ksplice-agent.service ksplice-prefetch.service ksplice.service >/dev/null 2>&1 || true
systemctl stop ksplice-agent.service ksplice-prefetch.service ksplice.service >/dev/null 2>&1 || true

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
OOMScoreAdjust=500
Environment=MALLOC_ARENA_MAX=2
Environment="JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=55 -XX:InitialRAMPercentage=20 -XX:MaxMetaspaceSize=128m -XX:MaxDirectMemorySize=32m -XX:ReservedCodeCacheSize=48m -Xss512k -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError -XX:ActiveProcessorCount=1 -Djava.security.egd=file:/dev/urandom -Djava.awt.headless=true"
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
swapon --show
free -m
systemctl status kingmaker-backend.service --no-pager -l | sed -n '1,25p'
systemctl list-timers kingmaker-backend-watchdog.timer --no-pager
