# Oracle VM deployment: `backend-api`

The Spring Boot backend lives under `project/backend-api` and currently runs on the Oracle Always Free VM.

## Current production endpoint

- `http://80.225.236.170`
- Health check: `http://80.225.236.170/healthz`
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

## Notes

- Desktop and Android can call the HTTP Oracle IP directly.
- GitHub Pages web is HTTPS, so browsers can block calls to the HTTP Oracle IP as mixed content until the backend has HTTPS/domain.
- If `CORS_ALLOWED_ORIGINS` is empty, the backend defaults to allowing only localhost.

## Current API

- `GET /healthz` no auth
- `GET /public/login-check` no auth
- `GET /public/android/latest` no auth
- `GET /api/me` requires `Authorization: Bearer <supabase_access_token>`
- `GET /api/funtarget/state` requires auth
- `POST /api/funtarget/intent` requires auth
