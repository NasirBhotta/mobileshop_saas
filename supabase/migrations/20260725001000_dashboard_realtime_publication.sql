-- Ensure every table watched by dashboardRealtimeRefreshProvider is published.
-- The loop is idempotent and safe for projects where some tables were enabled
-- manually from the Supabase dashboard.

do $block$
declare
  v_table text;
begin
  foreach v_table in array array[
    'products',
    'inventory',
    'sales',
    'customers',
    'customer_settlements',
    'mobile_service_transactions'
  ]
  loop
    if to_regclass(format('public.%I', v_table)) is not null
       and not exists (
         select 1
         from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = v_table
       ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        v_table
      );
    end if;
  end loop;
end
$block$;
