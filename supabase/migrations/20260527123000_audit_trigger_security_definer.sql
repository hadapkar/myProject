-- Ensure audit trigger can insert into audit_logs even when requests run under RLS.
-- (Backend now uses user JWT + anon key; no service_role required.)

create or replace function public.log_fun_target_state_changes()
returns trigger
language plpgsql
security definer
set search_path = public
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

