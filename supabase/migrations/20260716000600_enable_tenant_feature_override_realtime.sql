-- Publish entitlement changes so tenant apps can enforce platform-admin
-- feature and limit changes without requiring a manual refresh.

do $migration$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'tenant_feature_overrides'
  ) then
    alter publication supabase_realtime
      add table public.tenant_feature_overrides;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'tenant_limit_overrides'
  ) then
    alter publication supabase_realtime
      add table public.tenant_limit_overrides;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'plan_features'
  ) then
    alter publication supabase_realtime add table public.plan_features;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'plan_limits'
  ) then
    alter publication supabase_realtime add table public.plan_limits;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'features'
  ) then
    alter publication supabase_realtime add table public.features;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'plans'
  ) then
    alter publication supabase_realtime add table public.plans;
  end if;
end
$migration$;

alter table public.tenant_feature_overrides replica identity full;
alter table public.tenant_limit_overrides replica identity full;
alter table public.plan_features replica identity full;
alter table public.plan_limits replica identity full;
alter table public.features replica identity full;
alter table public.plans replica identity full;
