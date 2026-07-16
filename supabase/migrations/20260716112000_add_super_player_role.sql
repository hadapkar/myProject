-- Add SUPER_PLAYER role.
-- Role behavior in app/backend:
-- ADMIN: all admin features.
-- MANAGER: FunTarget Admin for PLAYER users.
-- SUPER_PLAYER: player gameplay plus FunTarget Admin for only their own row.
-- PLAYER: gameplay only.

alter table public.user_access
  drop constraint if exists user_access_role_valid;

alter table public.user_access
  add constraint user_access_role_valid check (role in ('ADMIN','MANAGER','SUPER_PLAYER','PLAYER'));