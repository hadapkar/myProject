-- User access / subscription management (per-user end date).
-- Admin manages rows; players can read their own row.

create table if not exists public.user_access (
  user_id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  role text not null default 'MANAGER', -- ADMIN | MANAGER
  status text not null default 'active', -- active | blocked
  ends_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_access_username_valid check (char_length(username) between 3 and 32),
  constraint user_access_role_valid check (role in ('ADMIN','MANAGER')),
  constraint user_access_status_valid check (status in ('active','blocked'))
);

create unique index if not exists user_access_username_uq on public.user_access (username);
create index if not exists user_access_ends_at_idx on public.user_access (ends_at);

alter table public.user_access enable row level security;

-- Self can read own row.
drop policy if exists "user_access_select_self" on public.user_access;
create policy "user_access_select_self"
on public.user_access
for select
to authenticated
using (user_id = auth.uid());

-- Admins can read all rows.
drop policy if exists "user_access_select_admin" on public.user_access;
create policy "user_access_select_admin"
on public.user_access
for select
to authenticated
using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

-- Admins can insert/update rows.
drop policy if exists "user_access_insert_admin" on public.user_access;
create policy "user_access_insert_admin"
on public.user_access
for insert
to authenticated
with check (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

drop policy if exists "user_access_update_admin" on public.user_access;
create policy "user_access_update_admin"
on public.user_access
for update
to authenticated
using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()))
with check (true);

