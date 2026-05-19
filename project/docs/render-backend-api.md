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
- `CORS_ALLOWED_ORIGINS` = `https://my-project-lg04pp43p-s-h-s-projects.vercel.app`

Render sets `PORT` automatically; `application.properties` reads it and the Dockerfile exposes `8080`.

## Verify

- Open: `https://<your-render-service>.onrender.com/healthz`
- Expect JSON: `{ "status": "ok", ... }`

## Current API

- `GET /healthz` (no auth)
- `GET /api/me` (requires `Authorization: Bearer <supabase_access_token>`)
