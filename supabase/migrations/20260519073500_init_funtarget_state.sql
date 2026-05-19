-- Initial schema for FunTarget "wheel/bet" game state.
-- Mirrors the current Salesforce CustomObject FunTargetState__c at a functional level.

-- Updated-at trigger helper
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.fun_target_state (
  id bigint generated always as identity primary key,
  user_id uuid not null unique references auth.users (id) on delete cascade,

  score numeric(16,2) not null default 1000,
  predefined_wheel_number smallint null check (predefined_wheel_number between 0 and 9),
  last10_results smallint[] not null default '{8,8,9,0,2,9,6,4,3,7}',
  total_bet_amount numeric(16,2) not null default 0,
  winner_amount numeric(16,2) not null default 0,
  bets_json jsonb not null default '{}'::jsonb,
  last_updated_from text not null default 'Site' check (last_updated_from in ('Site','Mobile','Admin')),
  last_round_at timestamptz null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_fun_target_state_set_updated_at on public.fun_target_state;
create trigger trg_fun_target_state_set_updated_at
before update on public.fun_target_state
for each row execute function public.set_updated_at();

alter table public.fun_target_state enable row level security;

-- Player can access only their own state row
drop policy if exists "fun_target_state_select_own" on public.fun_target_state;
create policy "fun_target_state_select_own"
on public.fun_target_state
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "fun_target_state_insert_own" on public.fun_target_state;
create policy "fun_target_state_insert_own"
on public.fun_target_state
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "fun_target_state_update_own" on public.fun_target_state;
create policy "fun_target_state_update_own"
on public.fun_target_state
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

