# Supabase (DB) in this repo

This repo uses the Supabase CLI to track database schema changes as migrations under `supabase/migrations/`.

## One-time setup

From repo root:

1. Initialize (already done):
   - `npx supabase init`
2. Login:
   - `npx supabase login`
3. Link this repo to your Supabase project:
   - `npx supabase link --project-ref <project_ref>`

`<project_ref>` is the subdomain part of your project URL, e.g. `https://<project_ref>.supabase.co`.

## Workflow

- Note: `supabase db pull` may require Docker Desktop on Windows. If you don't have Docker,
  prefer creating migrations manually (this repo starts with manual migrations).

- Create a new migration:
  - `npx supabase migration new <name>`
- Apply migrations to local dev:
  - `npx supabase start`
  - `npx supabase db reset`
- Push migrations to the linked remote project:
  - `npx supabase db push`

## Admin access (initial, minimal)

This repo uses a simple `public.admin_users` table for admin authorization in RLS policies.

- To grant admin to a user: insert their `auth.users.id` into `public.admin_users`.
  You can do this from Supabase SQL Editor.

## Hardening (constraints + audit)

Additional migrations add:

- Constraints on `public.fun_target_state` (valid last10 length/digits, bets_json shape, non-negative amounts)
- `public.audit_logs` with a trigger that logs inserts/updates to `fun_target_state`
