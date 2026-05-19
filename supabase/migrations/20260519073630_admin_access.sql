-- Minimal admin access model for the initial migration phase.
-- Mark a user as admin by inserting their auth.users id into public.admin_users.

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;

-- Admins can confirm they are admins (read their own row only)
drop policy if exists "admin_users_select_self" on public.admin_users;
create policy "admin_users_select_self"
on public.admin_users
for select
to authenticated
using (user_id = auth.uid());

-- fun_target_state: admins can read/update all rows
drop policy if exists "fun_target_state_select_admin" on public.fun_target_state;
create policy "fun_target_state_select_admin"
on public.fun_target_state
for select
to authenticated
using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

drop policy if exists "fun_target_state_update_admin" on public.fun_target_state;
create policy "fun_target_state_update_admin"
on public.fun_target_state
for update
to authenticated
using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()))
with check (true);

