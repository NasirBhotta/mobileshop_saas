-- Publish tenant status changes so an authenticated tenant app can react to
-- platform suspension/activation without a manual refresh.

do $migration$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tenants'
  ) then
    alter publication supabase_realtime add table public.tenants;
  end if;
end
$migration$;

-- UPDATE events only need the primary key and changed status. FULL identity
-- also makes old/new row data reliable for future access-control listeners.
alter table public.tenants replica identity full;
