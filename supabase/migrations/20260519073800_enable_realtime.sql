-- Enable Supabase Realtime on fun_target_state by adding it to the publication.
do $$
begin
  alter publication supabase_realtime add table public.fun_target_state;
exception
  when duplicate_object then
    null;
end $$;

