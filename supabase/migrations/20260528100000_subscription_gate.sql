-- Subscription gate (single-tenant / global).
-- When subscription is inactive/expired, backend denies access to /api/**.

create table if not exists public.app_subscription (
  id int primary key default 1,
  status text not null default 'active', -- active | inactive
  ends_at timestamptz null,
  updated_at timestamptz not null default now(),
  constraint app_subscription_singleton check (id = 1),
  constraint app_subscription_status_valid check (status in ('active','inactive'))
);

insert into public.app_subscription (id, status)
values (1, 'active')
on conflict (id) do nothing;

alter table public.app_subscription enable row level security;

-- Allow all authenticated users to read subscription state (for UI messaging).
drop policy if exists "app_subscription_select_authenticated" on public.app_subscription;
create policy "app_subscription_select_authenticated"
on public.app_subscription
for select
to authenticated
using (true);

-- Only admins can update subscription state.
drop policy if exists "app_subscription_update_admin" on public.app_subscription;
create policy "app_subscription_update_admin"
on public.app_subscription
for update
to authenticated
using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()))
with check (true);

