-- Package Patch 1: database-driven plans, features, subscriptions and overrides.
-- This migration seeds and enforces nothing, and public.tenants.plan remains untouched.

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  key text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  name text not null check (length(trim(name)) > 0),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint plans_deleted_inactive_check
    check (deleted_at is null or is_active = false)
);

create unique index plans_key_unique on public.plans (lower(key));
create index plans_active_idx on public.plans (is_active) where deleted_at is null;

create table public.features (
  id uuid primary key default gen_random_uuid(),
  key text not null check (
    key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
  ),
  module text not null check (length(trim(module)) > 0),
  name text not null check (length(trim(name)) > 0),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint features_deleted_inactive_check
    check (deleted_at is null or is_active = false)
);

create unique index features_key_unique on public.features (lower(key));
create index features_module_active_idx
on public.features (module, is_active) where deleted_at is null;

create table public.plan_features (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans(id) on delete restrict,
  feature_id uuid not null references public.features(id) on delete restrict,
  enabled boolean not null default true,
  reason text,
  is_active boolean not null default true,
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint plan_features_plan_feature_unique unique (plan_id, feature_id),
  constraint plan_features_dates_check
    check (expires_at is null or starts_at is null or expires_at > starts_at),
  constraint plan_features_deleted_inactive_check
    check (deleted_at is null or is_active = false)
);

create index plan_features_feature_idx on public.plan_features (feature_id);

create table public.plan_limits (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans(id) on delete restrict,
  key text not null check (key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  value numeric not null,
  reason text,
  is_active boolean not null default true,
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint plan_limits_plan_key_unique unique (plan_id, key),
  constraint plan_limits_dates_check
    check (expires_at is null or starts_at is null or expires_at > starts_at),
  constraint plan_limits_deleted_inactive_check
    check (deleted_at is null or is_active = false)
);

create index plan_limits_key_idx on public.plan_limits (key);

create table public.tenant_subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  plan_id uuid not null references public.plans(id) on delete restrict,
  status text not null default 'active' check (length(trim(status)) > 0),
  reason text,
  is_active boolean not null default true,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint tenant_subscriptions_dates_check
    check (expires_at is null or expires_at > starts_at),
  constraint tenant_subscriptions_deleted_inactive_check
    check (deleted_at is null or is_active = false)
);

create unique index tenant_subscriptions_one_active
on public.tenant_subscriptions (tenant_id)
where is_active and deleted_at is null;
create index tenant_subscriptions_plan_idx on public.tenant_subscriptions (plan_id);

create table public.tenant_feature_overrides (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  feature_id uuid not null references public.features(id) on delete restrict,
  enabled boolean not null,
  reason text,
  is_active boolean not null default true,
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint tenant_feature_overrides_dates_check
    check (expires_at is null or starts_at is null or expires_at > starts_at),
  constraint tenant_feature_overrides_deleted_inactive_check
    check (deleted_at is null or is_active = false)
);

create unique index tenant_feature_overrides_one_active
on public.tenant_feature_overrides (tenant_id, feature_id)
where is_active and deleted_at is null;
create index tenant_feature_overrides_expiry_idx
on public.tenant_feature_overrides (expires_at)
where is_active and deleted_at is null;

create table public.tenant_limit_overrides (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  key text not null check (key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  value numeric not null,
  reason text,
  is_active boolean not null default true,
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint tenant_limit_overrides_dates_check
    check (expires_at is null or starts_at is null or expires_at > starts_at),
  constraint tenant_limit_overrides_deleted_inactive_check
    check (deleted_at is null or is_active = false)
);

create unique index tenant_limit_overrides_one_active
on public.tenant_limit_overrides (tenant_id, key)
where is_active and deleted_at is null;
create index tenant_limit_overrides_expiry_idx
on public.tenant_limit_overrides (expires_at)
where is_active and deleted_at is null;

create table public.entitlement_audit_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete restrict,
  actor_user_id uuid references public.users(id) on delete set null,
  action text not null check (length(trim(action)) > 0),
  entity_type text not null check (length(trim(entity_type)) > 0),
  entity_id uuid,
  reason text,
  previous_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);

create index entitlement_audit_tenant_created_idx
on public.entitlement_audit_logs (tenant_id, created_at desc);
create index entitlement_audit_entity_idx
on public.entitlement_audit_logs (entity_type, entity_id);

create trigger plans_set_updated_at before update on public.plans
for each row execute function public.set_updated_at();
create trigger features_set_updated_at before update on public.features
for each row execute function public.set_updated_at();
create trigger plan_features_set_updated_at before update on public.plan_features
for each row execute function public.set_updated_at();
create trigger plan_limits_set_updated_at before update on public.plan_limits
for each row execute function public.set_updated_at();
create trigger tenant_subscriptions_set_updated_at
before update on public.tenant_subscriptions
for each row execute function public.set_updated_at();
create trigger tenant_feature_overrides_set_updated_at
before update on public.tenant_feature_overrides
for each row execute function public.set_updated_at();
create trigger tenant_limit_overrides_set_updated_at
before update on public.tenant_limit_overrides
for each row execute function public.set_updated_at();

alter table public.plans enable row level security;
alter table public.features enable row level security;
alter table public.plan_features enable row level security;
alter table public.plan_limits enable row level security;
alter table public.tenant_subscriptions enable row level security;
alter table public.tenant_feature_overrides enable row level security;
alter table public.tenant_limit_overrides enable row level security;
alter table public.entitlement_audit_logs enable row level security;

create policy "tenant users read effective subscription"
on public.tenant_subscriptions for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and is_active and deleted_at is null
  and starts_at <= now()
  and (expires_at is null or expires_at > now())
);

create policy "tenant users read subscribed plan"
on public.plans for select to authenticated
using (
  is_active and deleted_at is null
  and exists (
    select 1 from public.tenant_subscriptions s
    where s.plan_id = plans.id
      and s.tenant_id = public.current_user_tenant_id()
      and s.is_active and s.deleted_at is null
      and s.starts_at <= now()
      and (s.expires_at is null or s.expires_at > now())
  )
);

create policy "tenant users read effective plan features"
on public.plan_features for select to authenticated
using (
  is_active and deleted_at is null
  and (starts_at is null or starts_at <= now())
  and (expires_at is null or expires_at > now())
  and exists (
    select 1 from public.tenant_subscriptions s
    where s.plan_id = plan_features.plan_id
      and s.tenant_id = public.current_user_tenant_id()
      and s.is_active and s.deleted_at is null
      and s.starts_at <= now()
      and (s.expires_at is null or s.expires_at > now())
  )
);

create policy "tenant users read effective features"
on public.features for select to authenticated
using (
  is_active and deleted_at is null
  and (
    exists (
      select 1 from public.plan_features pf
      join public.tenant_subscriptions s on s.plan_id = pf.plan_id
      where pf.feature_id = features.id
        and pf.is_active and pf.deleted_at is null
        and (pf.starts_at is null or pf.starts_at <= now())
        and (pf.expires_at is null or pf.expires_at > now())
        and s.tenant_id = public.current_user_tenant_id()
        and s.is_active and s.deleted_at is null
        and s.starts_at <= now()
        and (s.expires_at is null or s.expires_at > now())
    )
    or exists (
      select 1 from public.tenant_feature_overrides o
      where o.feature_id = features.id
        and o.tenant_id = public.current_user_tenant_id()
        and o.is_active and o.deleted_at is null
        and (o.starts_at is null or o.starts_at <= now())
        and (o.expires_at is null or o.expires_at > now())
    )
  )
);

create policy "tenant users read effective plan limits"
on public.plan_limits for select to authenticated
using (
  is_active and deleted_at is null
  and (starts_at is null or starts_at <= now())
  and (expires_at is null or expires_at > now())
  and exists (
    select 1 from public.tenant_subscriptions s
    where s.plan_id = plan_limits.plan_id
      and s.tenant_id = public.current_user_tenant_id()
      and s.is_active and s.deleted_at is null
      and s.starts_at <= now()
      and (s.expires_at is null or s.expires_at > now())
  )
);

create policy "tenant users read effective feature overrides"
on public.tenant_feature_overrides for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and is_active and deleted_at is null
  and (starts_at is null or starts_at <= now())
  and (expires_at is null or expires_at > now())
);

create policy "tenant users read effective limit overrides"
on public.tenant_limit_overrides for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and is_active and deleted_at is null
  and (starts_at is null or starts_at <= now())
  and (expires_at is null or expires_at > now())
);

revoke all on table public.plans from anon, authenticated;
revoke all on table public.features from anon, authenticated;
revoke all on table public.plan_features from anon, authenticated;
revoke all on table public.plan_limits from anon, authenticated;
revoke all on table public.tenant_subscriptions from anon, authenticated;
revoke all on table public.tenant_feature_overrides from anon, authenticated;
revoke all on table public.tenant_limit_overrides from anon, authenticated;
revoke all on table public.entitlement_audit_logs from anon, authenticated;

grant select on table public.plans to authenticated;
grant select on table public.features to authenticated;
grant select on table public.plan_features to authenticated;
grant select on table public.plan_limits to authenticated;
grant select on table public.tenant_subscriptions to authenticated;
grant select on table public.tenant_feature_overrides to authenticated;
grant select on table public.tenant_limit_overrides to authenticated;

grant all privileges on table public.plans to service_role;
grant all privileges on table public.features to service_role;
grant all privileges on table public.plan_features to service_role;
grant all privileges on table public.plan_limits to service_role;
grant all privileges on table public.tenant_subscriptions to service_role;
grant all privileges on table public.tenant_feature_overrides to service_role;
grant all privileges on table public.tenant_limit_overrides to service_role;
grant all privileges on table public.entitlement_audit_logs to service_role;
