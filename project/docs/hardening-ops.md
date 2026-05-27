# Hardening Ops (Render + Supabase)

This doc covers the operational steps required after the hardening changes landed in code.

## 1) Render (backend-api) required env vars

Set these in your Render service:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server-only)
- `CORS_ALLOWED_ORIGINS` (required now)
- `RATE_LIMIT_PER_MINUTE` (optional; default `120`)

### CORS_ALLOWED_ORIGINS examples

Comma-separated origins, no trailing slashes. Examples:

- Local dev:
  - `http://localhost:3000,http://127.0.0.1:3000`
- GitHub Pages (Flutter web preview):
  - `https://hadapkar.github.io`
- Vercel:
  - `https://my-project-lg04pp43p-s-h-s-projects.vercel.app`

After updating env vars, trigger a redeploy on Render.

## 2) Apply Supabase migrations (prod)

The hardening migration is:

- `supabase/migrations/20260527090000_hardening.sql`

### Option A: Supabase CLI (recommended)

From repo root:

- `npx supabase link --project-ref <project_ref>` (one-time)
- `npx supabase db push`

### Option B: Supabase SQL Editor (manual)

If you can’t use the CLI, open Supabase Dashboard → SQL Editor and run the SQL in:

- `supabase/migrations/20260527090000_hardening.sql`

## 3) Verify

- Backend health:
  - `GET /healthz` returns `{ "status": "ok", ... }`
- Auth:
  - `GET /api/me` with `Authorization: Bearer <supabase_access_token>` returns your id/email
- Game:
  - Flutter web/desktop can load `GET /api/funtarget/state`

