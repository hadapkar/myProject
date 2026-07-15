# Oracle VM deployment: `backend-api`

The Spring Boot backend lives under `project/backend-api` and currently runs on the Oracle Always Free VM behind nginx.

## Current production endpoint

- Public endpoint: `http://80.225.236.170`
- Public liveness check: `http://80.225.236.170/healthz`
- Public readiness check: `http://80.225.236.170/readyz`
- Public reverse proxy: `nginx` on port `80`
- Backend service: `kingmaker-backend` on `127.0.0.1:8080`
- Backend env file: `/etc/kingmaker-backend.env`

## Required environment variables

- `PORT=8080`
- `SERVER_ADDRESS=127.0.0.1`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `CORS_ALLOWED_ORIGINS` if browser/web clients are used
- `RATE_LIMIT_PER_MINUTE` optional, default `120`
- `REQUEST_MAX_BYTES` optional, default `32768`

## Restart

After changing the env file or backend jar:

```bash
sudo systemctl restart kingmaker-backend
sudo systemctl status kingmaker-backend
curl http://127.0.0.1:8080/healthz
curl http://80.225.236.170/healthz
```

After changing nginx config:

```bash
sudo nginx -t
sudo systemctl restart nginx
curl http://80.225.236.170/healthz
```

## Backend watchdog

Install the watchdog on the Oracle VM after deployment or after a VM rebuild:

```bash
cd /opt/kingmaker/backend-api
sudo bash ops/install-oracle-watchdog.sh
```

What it does:

- Keeps `kingmaker-backend` under `Restart=always`.
- Runs a local `http://127.0.0.1:8080/healthz` check every 30 seconds.
- Gives Spring Boot 120 seconds of startup grace before health failures count.
- Restarts `kingmaker-backend` after 3 failed local health checks.
- Applies systemd memory/task limits so the backend restarts before it can starve the tiny VM.
- Applies low-memory JVM defaults for heap/metaspace/GC on the Always Free VM.
- Enables bounded persistent journald logs for future RCA.

This fixes a hung Java/backend process. If the whole Oracle VM or SSH daemon freezes, use Oracle Console auto-recovery/hard reboot; no in-VM watchdog can recover an OS-level freeze.

## Nginx reverse proxy

Install or reapply nginx hardening on the Oracle VM:

```bash
cd /opt/kingmaker/backend-api
sudo bash ops/install-oracle-nginx-proxy.sh
```

What it does:

- Installs nginx if missing.
- Moves Spring Boot to `127.0.0.1:8080`.
- Keeps public traffic on nginx port `80`.
- Adds per-IP connection and request limits.
- Adds proxy timeouts so slow clients do not pin backend threads.
- Keeps Android APK downloads as redirects to GitHub instead of serving large files from Oracle.

## Notes

- Desktop and Android can call the HTTP Oracle IP directly.
- GitHub Pages web is HTTPS, so browsers can block calls to the HTTP Oracle IP as mixed content until the backend has HTTPS/domain.
- If `CORS_ALLOWED_ORIGINS` is empty, the backend defaults to allowing only localhost.

## Current API

- `GET /healthz` no auth
- `GET /readyz` no auth
- `GET /public/login-check` no auth
- `GET /public/android/latest` no auth
- `GET /api/me` requires `Authorization: Bearer <supabase_access_token>`
- `GET /api/funtarget/state` requires auth
- `POST /api/funtarget/intent` requires auth
