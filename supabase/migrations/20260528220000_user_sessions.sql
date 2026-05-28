-- Enforce single active session per user per platform group.
-- Platform groups: desktop (web+desktop) and mobile.

create table if not exists public.user_sessions (
  user_id uuid not null references auth.users (id) on delete cascade,
  platform_group text not null,
  session_id uuid not null,
  device_id text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_sessions_platform_valid check (platform_group in ('desktop','mobile')),
  primary key (user_id, platform_group)
);

create index if not exists user_sessions_session_id_idx on public.user_sessions (session_id);

alter table public.user_sessions enable row level security;

-- Self can read own session row.
drop policy if exists "user_sessions_select_self" on public.user_sessions;
create policy "user_sessions_select_self"
on public.user_sessions
for select
to authenticated
using (user_id = auth.uid());

-- Admins can read all.
drop policy if exists "user_sessions_select_admin" on public.user_sessions;
create policy "user_sessions_select_admin"
on public.user_sessions
for select
to authenticated
using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

-- No direct writes from clients. Backend uses service_role.

