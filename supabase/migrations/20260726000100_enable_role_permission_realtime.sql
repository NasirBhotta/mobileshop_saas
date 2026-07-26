-- Refresh staff permission decisions while their session is already open.
-- This is intentionally separate from subscription/entitlement realtime.

do $migration$
declare
  table_name text;
begin
  foreach table_name in array array[
    'roles',
    'role_permissions',
    'user_role_assignments'
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

alter table public.roles replica identity full;
alter table public.role_permissions replica identity full;
alter table public.user_role_assignments replica identity full;
