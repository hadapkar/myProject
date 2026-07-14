-- Add PLAYER below MANAGER and ADMIN.
-- Role hierarchy in app UI/backend: ADMIN > MANAGER > PLAYER.

alter table public.user_access
  alter column role set default 'PLAYER';

alter table public.user_access
  drop constraint if exists user_access_role_valid;

alter table public.user_access
  add constraint user_access_role_valid check (role in ('ADMIN','MANAGER','PLAYER'));
-- Managers can read only PLAYER game state rows. Admins retain full access via admin_users policies.
drop policy if exists "fun_target_state_select_manager_players" on public.fun_target_state;
create policy "fun_target_state_select_manager_players"
on public.fun_target_state
for select
to authenticated
using (
  exists (
    select 1
    from public.user_access self_access
    where self_access.user_id = auth.uid()
      and self_access.role = 'MANAGER'
  )
  and exists (
    select 1
    from public.user_access target_access
    where target_access.user_id = public.fun_target_state.user_id
      and target_access.role = 'PLAYER'
  )
);