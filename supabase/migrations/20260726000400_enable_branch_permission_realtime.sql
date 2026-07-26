-- Keep branch-aware permission decisions fresh in already-open staff apps.

do $migration$
declare
  table_name text;
begin
  foreach table_name in array array[
    'user_branch_role_assignments',
    'user_branch_permission_overrides'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end
$migration$;

alter table public.user_branch_role_assignments replica identity full;
alter table public.user_branch_permission_overrides replica identity full;
