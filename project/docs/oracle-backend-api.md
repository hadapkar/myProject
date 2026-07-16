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


## CI-built backend deploy with rollback

The backend jar should be built by GitHub Actions, not on the 1 GB Oracle VM. The workflow is `.github/workflows/backend-api-deploy.yml`.

What it does:

- Builds and tests `project/backend-api` on GitHub using Java 21.
- Uploads `backend-api-0.0.1-SNAPSHOT.jar` as a workflow artifact.
- Copies the jar to Oracle only when `ORACLE_SSH_PRIVATE_KEY` is configured as a GitHub Actions secret.
- Runs `ops/deploy-oracle-backend-jar.sh` on the VM.
- Keeps the previous jar as `backend-api-0.0.1-SNAPSHOT.jar.previous`.
- Restarts only `kingmaker-backend`, waits for `/readyz`, and automatically restores the previous jar if readiness fails.

Required GitHub Actions secrets for automatic deploy:

- `ORACLE_SSH_PRIVATE_KEY`: private key that can SSH to the VM as `opc`.
- `ORACLE_HOST`: optional, defaults to `80.225.236.170`.
- `ORACLE_USER`: optional, defaults to `opc`.

If `ORACLE_SSH_PRIVATE_KEY` is missing, the workflow still builds/tests the jar but skips deployment.

Manual VM-side rollback deploy command:

```bash
sudo bash /tmp/deploy-oracle-backend-jar.sh /tmp/backend-api-0.0.1-SNAPSHOT.jar
```

## Android update metadata sync

Android APK publishing and Oracle update metadata are automated when the Android
workflow has Oracle SSH access:

- The APK workflow publishes `KingMaker.apk`, `KingMaker.apk.sha256`, and
  `KingMaker.apk.size` to the `android-latest` GitHub Release.
- After publishing, the workflow updates `/etc/kingmaker-backend.env` on Oracle
  and restarts only `kingmaker-backend`.
- If `ORACLE_SSH_PRIVATE_KEY` is missing, APK publishing still succeeds but
  Oracle metadata sync is skipped.

The env values used by the backend are:

- `ANDROID_LATEST_VERSION`
- `ANDROID_LATEST_BUILD`
- `ANDROID_SOURCE_APK_URL`
- `ANDROID_APK_SHA256`
- `ANDROID_APK_SIZE_BYTES`

Keep these aligned with the APK release, or the mobile app will not see the
intended update.
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
- Adds a 1.5 GB swapfile when no swap exists, so short memory spikes do not freeze Linux userspace.
- Applies low-memory kernel settings for the 1 GB VM.
- Disables automatic `dnf` metadata refresh, `mlocate` indexing, and Ksplice background jobs that can spike memory on the 1 GB VM.
- Keeps Oracle Cloud Agent enabled so console monitoring/run-command remains available.
- Applies low-memory JVM defaults for heap/metaspace/direct memory/code cache/GC on the Always Free VM.
- Marks Java as the preferred OOM victim, so the backend restarts before SSH/nginx/the OS become unresponsive.
- Enables bounded persistent journald logs for future RCA.

This fixes a hung Java/backend process and reduces the chance that the 1 GB VM freezes under memory pressure. If the whole Oracle VM or SSH daemon freezes, use Oracle Console force reboot; no in-VM watchdog can recover an OS-level freeze once Linux userspace stops responding.


## RCA: July 15, 2026 VM hang

The VM did not fail because of a Render-style cold start. Persistent journal logs from the previous boot showed an OS-level out-of-memory event:

- `dnf` package metadata refresh was started by background maintenance.
- `dnf` reached roughly 690 MB resident memory on a 1 GB VM.
- The kernel invoked the OOM killer.
- After memory pressure, Linux userspace became unhealthy enough that HTTP and SSH stopped responding.

The mitigation is to keep package/search/kernel patch refresh manual on the 1 GB VM. Manual package updates still work, but should be run intentionally during a maintenance window.

## 1 GB VM fallback

`VM.Standard.A1.Flex` is the preferred Always Free target, but it is often out of capacity. When A1 is unavailable, keep the current `VM.Standard.E2.1.Micro` and reapply the watchdog script after deployments or VM rebuilds:

```bash
cd /opt/kingmaker/backend-api
sudo bash ops/install-oracle-watchdog.sh
```

For the 1 GB VM, avoid building large artifacts on the VM while users are active. Build with Gradle using `--no-daemon --max-workers=1`, then restart only `kingmaker-backend`.

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
