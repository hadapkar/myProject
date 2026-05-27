# Render deployment: `backend-api`

This repo is a monorepo. The Spring Boot backend lives under `project/backend-api`.

## Create Render service (manual)

1. Render dashboard → **New** → **Web Service**
2. Select GitHub repo: `hadapkar/myProject`
3. Branch: `main`
4. **Root Directory**: `project/backend-api`
5. **Language**: `Docker`

### Build & start

Docker uses `project/backend-api/Dockerfile`.

### Environment variables

- `SUPABASE_URL` = `https://ydljofhkpeusxoegnvfs.supabase.co`
- `SUPABASE_ANON_KEY` = (your Supabase anon key)
- `SUPABASE_SERVICE_ROLE_KEY` = (your Supabase service_role key, server-only)
- `CORS_ALLOWED_ORIGINS` = comma-separated list of browser origins allowed to call the API, e.g.
  - `https://hadapkar.github.io` (Flutter Web on GitHub Pages)
  - `http://localhost:3000` (local dev)
- `RATE_LIMIT_PER_MINUTE` = per-user/IP limit for `/api/*` (default `120`)

Render sets `PORT` automatically; `application.properties` reads it and the Dockerfile exposes `8080`.

## Notes

- If `CORS_ALLOWED_ORIGINS` is empty, the backend defaults to allowing only localhost. Set it explicitly on Render.

## Verify

- Open: `https://<your-render-service>.onrender.com/healthz`
- Expect JSON: `{ "status": "ok", ... }`

## Current API

- `GET /healthz` (no auth)
- `GET /api/me` (requires `Authorization: Bearer <supabase_access_token>`)
- `GET /api/funtarget/state` (requires auth)
- `POST /api/funtarget/intent` (requires auth)
