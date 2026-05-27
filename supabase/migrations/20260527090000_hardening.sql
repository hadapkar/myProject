-- Hardening: constraints, indexes, and audit logging.

-- Basic numeric guards
alter table public.fun_target_state
  drop constraint if exists fun_target_state_score_nonnegative,
  add constraint fun_target_state_score_nonnegative check (score >= 0);

alter table public.fun_target_state
  drop constraint if exists fun_target_state_total_bet_nonnegative,
  add constraint fun_target_state_total_bet_nonnegative check (total_bet_amount >= 0);

alter table public.fun_target_state
  drop constraint if exists fun_target_state_winner_nonnegative,
  add constraint fun_target_state_winner_nonnegative check (winner_amount >= 0);

-- last10_results should always be 10 digits between 0..9
alter table public.fun_target_state
  drop constraint if exists fun_target_state_last10_len_10,
  add constraint fun_target_state_last10_len_10 check (array_length(last10_results, 1) = 10);

alter table public.fun_target_state
  drop constraint if exists fun_target_state_last10_digits,
  add constraint fun_target_state_last10_digits
    check (
      not exists (
        select 1
        from unnest(last10_results) v
        where v < 0 or v > 9
      )
    );

-- bets_json should be an object with keys 0..9 and numeric values >= 0
alter table public.fun_target_state
  drop constraint if exists fun_target_state_bets_json_object,
  add constraint fun_target_state_bets_json_object check (jsonb_typeof(bets_json) = 'object');

alter table public.fun_target_state
  drop constraint if exists fun_target_state_bets_json_keys_0_9,
  add constraint fun_target_state_bets_json_keys_0_9
    check (
      not exists (
        select 1
        from jsonb_object_keys(bets_json) k
        where k !~ '^[0-9]$'
      )
    );

alter table public.fun_target_state
  drop constraint if exists fun_target_state_bets_json_values_numeric,
  add constraint fun_target_state_bets_json_values_numeric
    check (
      not exists (
        select 1
        from jsonb_each(bets_json) e
        where jsonb_typeof(e.value) not in ('number','string')
           or (e.value #>> '{}') !~ '^[0-9]+(\.[0-9]+)?$'
      )
    );

-- Helpful index for admin dashboards / realtime ordering
create index if not exists idx_fun_target_state_updated_at
  on public.fun_target_state (updated_at desc);

-- Audit log table (minimal, server/admin readable)
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_user_id uuid null,
  actor_role text null,
  action text not null,
  target_user_id uuid null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_created_at on public.audit_logs (created_at desc);
create index if not exists idx_audit_logs_actor on public.audit_logs (actor_user_id, created_at desc);
create index if not exists idx_audit_logs_target on public.audit_logs (target_user_id, created_at desc);

alter table public.audit_logs enable row level security;

-- Only admins can read audit logs.
drop policy if exists "audit_logs_select_admin" on public.audit_logs;
create policy "audit_logs_select_admin"
on public.audit_logs
for select
to authenticated
using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

-- No inserts/updates/deletes allowed from anon/authenticated directly (service_role bypasses anyway).

create or replace function public._request_jwt_role()
returns text
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.role', true), '');
$$;

create or replace function public.log_fun_target_state_changes()
returns trigger
language plpgsql
as $$
declare
  actor uuid;
  role text;
begin
  actor := auth.uid();
  role := public._request_jwt_role();

  if (tg_op = 'INSERT') then
    insert into public.audit_logs(actor_user_id, actor_role, action, target_user_id, payload)
    values (
      actor,
      role,
      'funtarget_state_insert',
      new.user_id,
      jsonb_build_object(
        'score', new.score,
        'total_bet_amount', new.total_bet_amount,
        'winner_amount', new.winner_amount,
        'last_updated_from', new.last_updated_from
      )
    );
    return new;
  end if;

  if (tg_op = 'UPDATE') then
    insert into public.audit_logs(actor_user_id, actor_role, action, target_user_id, payload)
    values (
      actor,
      role,
      'funtarget_state_update',
      new.user_id,
      jsonb_build_object(
        'from', jsonb_build_object(
          'score', old.score,
          'total_bet_amount', old.total_bet_amount,
          'winner_amount', old.winner_amount,
          'bets_json', old.bets_json,
          'predefined_wheel_number', old.predefined_wheel_number,
          'last_round_at', old.last_round_at,
          'last_updated_from', old.last_updated_from
        ),
        'to', jsonb_build_object(
          'score', new.score,
          'total_bet_amount', new.total_bet_amount,
          'winner_amount', new.winner_amount,
          'bets_json', new.bets_json,
          'predefined_wheel_number', new.predefined_wheel_number,
          'last_round_at', new.last_round_at,
          'last_updated_from', new.last_updated_from
        )
      )
    );
    return new;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_fun_target_state_audit on public.fun_target_state;
create trigger trg_fun_target_state_audit
after insert or update on public.fun_target_state
for each row execute function public.log_fun_target_state_changes();
