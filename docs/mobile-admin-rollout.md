# Mobile Admin Rollout (King Maker)

This is the production checklist for the Android **admin** app:
- Same login + access rules as web/desktop
- On mobile, the **FunTarget tile opens the admin portal**

## 1) Supabase (DB)

Run these migrations in Supabase SQL Editor (in this order if not already applied):
- `supabase/migrations/20260519073500_init_funtarget_state.sql`
- `supabase/migrations/20260519073630_admin_access.sql`
- `supabase/migrations/20260519073800_enable_realtime.sql`
- `supabase/migrations/20260527090000_hardening.sql`
- `supabase/migrations/20260528100000_subscription_gate.sql`
- `supabase/migrations/20260528121500_user_access.sql`
- `supabase/migrations/20260528220000_user_sessions.sql`

Then, ensure your admin user is present:
- `public.admin_users` must contain the admin `auth.users.id`
- `public.user_access` should contain the admin user with role `ADMIN`

## 2) Render (backend-api)

Environment variables required:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (required for admin actions + sessions)
- `CORS_ALLOWED_ORIGINS` (include your web URL(s) if used)

Deploy the latest `main` to Render.

Quick sanity checks:
- `GET /healthz` returns OK
- Admin can call `GET /api/admin/funtarget/states` (authenticated bearer)

## 3) Android APK (GitHub Actions)

Workflow:
- **Actions → Flutter Android APK**

Download artifact:
- `kingmaker-android-apk` → contains `app-release.apk`

Install on Android:
- Copy APK to device → open → allow “Install unknown apps”
- Launch **King Maker**

Expected behavior:
- Admin user: FunTarget tile opens **FunTarget Admin**
- Manager user: FunTarget tile shows **Admins only**

## 4) Firebase App Distribution (optional, recommended)

Add these GitHub secrets:
- `FIREBASE_SERVICE_ACCOUNT_JSON` (service account key JSON)
- `FIREBASE_APP_ID` (Android app id in Firebase)
- `FIREBASE_GROUPS` (comma-separated groups, e.g. `testers`) **or**
- `FIREBASE_TESTERS` (comma-separated emails, e.g. `you@example.com,qa@example.com`)

Run workflow:
- **Actions → Firebase App Distribution (Android) → Run workflow**
