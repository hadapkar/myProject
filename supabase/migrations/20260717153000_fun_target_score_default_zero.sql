-- New FunTarget state rows should start with zero balance.
-- Existing player scores are intentionally left unchanged.

alter table public.fun_target_state
  alter column score set default 0;