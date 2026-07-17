-- Add parent ownership to user_access for role hierarchy.
-- Admin sees all users. Managers can manage only PLAYER users assigned to them.
-- Parent options are intended to be ADMIN or MANAGER users.

alter table public.user_access
  add column if not exists parent_user_id uuid null references auth.users (id) on delete set null;

create index if not exists user_access_parent_user_id_idx
  on public.user_access (parent_user_id);

alter table public.user_access
  drop constraint if exists user_access_parent_not_self;

alter table public.user_access
  add constraint user_access_parent_not_self
  check (parent_user_id is null or parent_user_id <> user_id);
