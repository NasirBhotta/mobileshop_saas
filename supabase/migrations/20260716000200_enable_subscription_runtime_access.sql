-- Allow tenant apps to observe their own current subscription lifecycle and
-- publish platform-admin changes through Supabase Realtime.

drop policy if exists "tenant users read effective subscription"
on public.tenant_subscriptions;

create policy "tenant users read own current subscription"
on public.tenant_subscriptions
for select
to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and is_active
  and deleted_at is null
);

do $migration$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tenant_subscriptions'
  ) then
    alter publication supabase_realtime
      add table public.tenant_subscriptions;
  end if;
end
$migration$;

alter table public.tenant_subscriptions replica identity full;
