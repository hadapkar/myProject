# Oracle VM deployment: `backend-api`

The Spring Boot backend lives under `project/backend-api` and currently runs on the Oracle Always Free VM.

## Current production endpoint

- `http://80.225.236.170`
- Liveness check: `http://80.225.236.170/healthz`
- Readiness check: `http://80.225.236.170/readyz`
- systemd service: `kingmaker-backend`
- env file: `/etc/kingmaker-backend.env`

## Required environment variables

- `PORT=80`
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
- Runs a local `http://127.0.0.1/healthz` check every 30 seconds.
- Restarts `kingmaker-backend` after a failed local health check.
- Applies systemd memory/task limits so the backend restarts before it can starve the tiny VM.
- Applies low-memory JVM defaults for heap/metaspace/GC on the Always Free VM.

This fixes a hung Java/backend process. If the whole Oracle VM or SSH daemon freezes, use Oracle Console auto-recovery/hard reboot; no in-VM watchdog can recover an OS-level freeze.

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
