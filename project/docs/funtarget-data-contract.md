# FunTarget – Data Contract (Supabase)

This document describes the **minimal** database contract needed to reproduce the current FunTarget behavior (as implemented in the Salesforce LWC) in the new stack (Flutter desktop + Supabase + backend on Render).

Source of truth: `supabase/migrations/`.

## Tables

### `public.fun_target_state`

One row per authenticated user (`user_id`).

Key columns (current schema: `supabase/migrations/20260519073500_init_funtarget_state.sql`):

- `user_id (uuid, unique)` — references `auth.users.id`.
- `score (numeric(16,2))` — player balance shown in UI.
- `total_bet_amount (numeric(16,2))` — sum of the current bet JSON.
- `winner_amount (numeric(16,2))` — last computed winner amount.
- `bets_json (jsonb)` — map of wheel numbers to bet amounts.
- `predefined_wheel_number (smallint, nullable)` — optional forced result (0–9), set by Admin.
- `last10_results (smallint[])` — last 10 wheel outcomes.
- `last_updated_from (text)` — one of `Site`, `Mobile`, `Admin` (useful for audit/debug).
- `last_round_at (timestamptz, nullable)` — timestamp anchor used for round timing.

### `public.admin_users`

Simple admin allow-list table used by RLS policies to allow admin reads/updates.

Schema: `supabase/migrations/20260519073630_admin_access.sql`.

## Timing rules (important)

To avoid timer jumps/drift (issue seen in mobile/web), **all clients must anchor the round timer from `last_round_at`** and use the same convention:

- A “round” is 60 seconds: `00:59` down to `00:00`.
- `last_round_at` is updated **once per round**, at a single consistent event.

Recommended convention (matches the latest Salesforce changes):

- Update `last_round_at` **only when the spin result is finalized** (end-of-round / result moment).
- Update `last10_results` at the same time (append the new result).
- Clear `predefined_wheel_number` after the result is applied (optional, but must be consistent across clients).

Client timer (Flutter and any future clients):

- If `last_round_at` exists: `time_left = 59 - floor((now - last_round_at) % 60)`.
- If `last_round_at` is `null`: show a neutral state (do not fake a default last10/timer).

## Realtime

`supabase/migrations/20260519073800_enable_realtime.sql` enables realtime for `fun_target_state`.

Admin dashboards (future Android app) should subscribe to database changes instead of polling:

- subscribe to `public.fun_target_state` changes
- subscribe to `public.admin_users` changes (optional)

## What the backend (Render) will enforce

The Flutter client keeps most game logic client-side for UX, but the backend should validate:

- bet JSON shape and range (0–9 keys, numeric amounts)
- total bet math (server recomputes from JSON)
- result finalization event updates `last_round_at` only in the chosen place

We will keep this minimal and migration-friendly: no extra features, just validation and consistency.

