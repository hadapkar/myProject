#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo bash project/backend-api/ops/install-oracle-nginx-proxy.sh" >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  dnf -y --setopt=timeout=15 --setopt=retries=1 \
    --disablerepo=ol9_ksplice \
    --disablerepo=ol9_UEKR8 \
    --disablerepo=ol9_oci_included \
    install nginx
fi

backup="/etc/nginx/nginx.conf.kingmaker.bak.$(date +%Y%m%d%H%M%S)"
cp -a /etc/nginx/nginx.conf "$backup"

cat >/etc/nginx/nginx.conf <<'NGINX'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 256;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 15s;
    server_tokens off;

    limit_req_zone $binary_remote_addr zone=kingmaker_api:10m rate=20r/s;
    limit_conn_zone $binary_remote_addr zone=kingmaker_conn:10m;

    upstream kingmaker_backend {
        server 127.0.0.1:8080;
        keepalive 8;
    }

    server {
        listen 80 default_server;
        server_name _;

        client_max_body_size 64k;
        client_body_timeout 10s;
        client_header_timeout 10s;
        send_timeout 15s;
        limit_req_status 429;
        limit_conn_status 429;

        location / {
            limit_conn kingmaker_conn 20;
            limit_req zone=kingmaker_api burst=40 nodelay;

            proxy_pass http://kingmaker_backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 3s;
            proxy_send_timeout 15s;
            proxy_read_timeout 15s;
            proxy_buffering on;
            proxy_buffers 8 16k;
            proxy_busy_buffers_size 32k;
        }
    }
}
NGINX

if command -v getsebool >/dev/null 2>&1 && getsebool httpd_can_network_connect >/dev/null 2>&1; then
  timeout 120 setsebool -P httpd_can_network_connect on || setsebool httpd_can_network_connect on || true
fi

tmp_env="$(mktemp)"
awk '!/^(PORT|SERVER_ADDRESS)=/' /etc/kingmaker-backend.env >"$tmp_env"
printf 'PORT=8080\nSERVER_ADDRESS=127.0.0.1\n' >>"$tmp_env"
install -m 600 -o root -g root "$tmp_env" /etc/kingmaker-backend.env
rm -f "$tmp_env"

if [ -x /usr/local/bin/kingmaker-backend-watchdog ]; then
  sed -i 's|^HEALTH_URL=.*|HEALTH_URL="${KINGMAKER_BACKEND_HEALTH_URL:-http://127.0.0.1:8080/healthz}"|' /usr/local/bin/kingmaker-backend-watchdog
fi

nginx -t
systemctl enable nginx >/dev/null
systemctl restart kingmaker-backend
sleep 75
curl -fsS --max-time 8 http://127.0.0.1:8080/healthz >/dev/null
systemctl restart nginx
systemctl restart kingmaker-backend-watchdog.timer
systemctl is-active kingmaker-backend
systemctl is-active nginx
systemctl is-active kingmaker-backend-watchdog.timer
ss -ltnp | egrep ':80|:8080|:22'
