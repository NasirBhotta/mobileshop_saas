-- Dashboard listens for customer payment/settlement changes. Supabase rejects
-- the whole channel when a subscribed table is absent from this publication.

do $block$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'customer_settlements'
  ) then
    alter publication supabase_realtime
      add table public.customer_settlements;
  end if;
end
$block$;
