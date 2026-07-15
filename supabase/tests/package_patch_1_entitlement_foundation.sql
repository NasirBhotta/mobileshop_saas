-- Run against a disposable/local database after applying all migrations.
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000311',
   'authenticated', 'authenticated', 'tenant-a-p1@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000312',
   'authenticated', 'authenticated', 'tenant-b-p1@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000311',
   'Package 1 Tenant A', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000312',
   'Package 1 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000311',
   '00000000-0000-4000-8000-000000000311',
   'Package 1 User A', 'tenant-a-p1@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000312',
   '00000000-0000-4000-8000-000000000312',
   'Package 1 User B', 'tenant-b-p1@example.invalid', 'owner');

-- Trusted backend setup. These are rollback-only fixtures, not product seeds.
insert into public.plans (id, key, name) values
  ('00000000-0000-4000-8000-000000000313', 'package_test_a', 'Package Test A'),
  ('00000000-0000-4000-8000-000000000314', 'package_test_b', 'Package Test B');

insert into public.features (id, key, module, name) values
  ('00000000-0000-4000-8000-000000000315',
   'reports.test_feature', 'reports', 'Test report feature'),
  ('00000000-0000-4000-8000-000000000316',
   'inventory.test_feature', 'inventory', 'Test inventory feature');

insert into public.plan_features (plan_id, feature_id, enabled) values
  ('00000000-0000-4000-8000-000000000313',
   '00000000-0000-4000-8000-000000000315', true),
  ('00000000-0000-4000-8000-000000000314',
   '00000000-0000-4000-8000-000000000316', true);

insert into public.plan_limits (plan_id, key, value) values
  ('00000000-0000-4000-8000-000000000313', 'branch.max_count', 3),
  ('00000000-0000-4000-8000-000000000314', 'branch.max_count', 7);

insert into public.tenant_subscriptions (tenant_id, plan_id) values
  ('00000000-0000-4000-8000-000000000311',
   '00000000-0000-4000-8000-000000000313'),
  ('00000000-0000-4000-8000-000000000312',
   '00000000-0000-4000-8000-000000000314');

insert into public.tenant_feature_overrides (
  tenant_id, feature_id, enabled, reason, expires_at
) values (
  '00000000-0000-4000-8000-000000000311',
  '00000000-0000-4000-8000-000000000316',
  true, 'Expired test override', now() - interval '1 hour'
);

insert into public.tenant_limit_overrides (
  tenant_id, key, value, reason, expires_at
) values (
  '00000000-0000-4000-8000-000000000311',
  'branch.max_count', 10, 'Temporary test limit', now() + interval '1 day'
);

insert into public.entitlement_audit_logs (
  tenant_id, action, entity_type, entity_id, reason, new_value
) values (
  '00000000-0000-4000-8000-000000000311',
  'override.created', 'tenant_feature_override',
  '00000000-0000-4000-8000-000000000316',
  'Backend audit fixture', '{"enabled": true}'::jsonb
);

do $test$
begin
  begin
    insert into public.plans (key, name)
    values ('package_test_a', 'Duplicate plan');
    raise exception 'Duplicate plan key unexpectedly succeeded';
  exception when unique_violation then null;
  end;

  begin
    insert into public.features (key, module, name)
    values ('reports.test_feature', 'reports', 'Duplicate feature');
    raise exception 'Duplicate feature key unexpectedly succeeded';
  exception when unique_violation then null;
  end;

  if not exists (
    select 1 from public.tenant_feature_overrides
    where expires_at <= now() and is_active and deleted_at is null
  ) then
    raise exception 'Expired overrides cannot be identified by trusted backend';
  end if;

  update public.plans set description = 'Backend-managed'
  where id = '00000000-0000-4000-8000-000000000313';
  if (select description from public.plans
      where id = '00000000-0000-4000-8000-000000000313') <> 'Backend-managed' then
    raise exception 'Trusted backend plan update failed';
  end if;

  if not has_table_privilege('service_role', 'public.plans', 'INSERT,UPDATE,DELETE')
     or not has_table_privilege(
       'service_role', 'public.tenant_feature_overrides', 'INSERT,UPDATE,DELETE'
     ) then
    raise exception 'service_role does not retain entitlement management privileges';
  end if;

  if has_table_privilege('anon', 'public.plans', 'SELECT')
     or has_table_privilege('anon', 'public.tenant_subscriptions', 'SELECT')
     or has_table_privilege('authenticated', 'public.plans', 'INSERT')
     or has_table_privilege(
       'authenticated', 'public.tenant_feature_overrides', 'UPDATE'
     ) then
    raise exception 'Untrusted roles retain entitlement mutation/access privileges';
  end if;

  if not (select relrowsecurity from pg_class
          where oid = 'public.plans'::regclass)
     or not (select relrowsecurity from pg_class
             where oid = 'public.tenant_subscriptions'::regclass)
     or not (select relrowsecurity from pg_class
             where oid = 'public.tenant_feature_overrides'::regclass) then
    raise exception 'Entitlement RLS is not enabled';
  end if;
end
$test$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000311',
  true
);

do $test$
declare
  visible_count integer;
begin
  select count(*) into visible_count from public.plans;
  if visible_count <> 1 then
    raise exception 'Tenant A sees % plans; expected its subscribed plan only', visible_count;
  end if;
  if not exists (
    select 1 from public.features where key = 'reports.test_feature'
  ) or exists (
    select 1 from public.features where key = 'inventory.test_feature'
  ) then
    raise exception 'Tenant A feature isolation failed';
  end if;
  if (select count(*) from public.tenant_subscriptions) <> 1
     or (select count(*) from public.plan_limits) <> 1
     or (select count(*) from public.tenant_limit_overrides) <> 1 then
    raise exception 'Tenant A effective subscription read failed';
  end if;
  if exists (select 1 from public.tenant_feature_overrides) then
    raise exception 'Expired feature override was exposed as effective';
  end if;

  begin
    insert into public.plans (key, name) values ('client_plan', 'Client Plan');
    raise exception 'Authenticated plan insert unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    update public.tenant_limit_overrides set value = 999;
    raise exception 'Authenticated override update unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;

  begin
    delete from public.tenant_subscriptions;
    raise exception 'Authenticated subscription delete unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;
end
$test$;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000312',
  true
);

do $test$
begin
  if exists (
    select 1 from public.plans where key = 'package_test_a'
  ) or not exists (
    select 1 from public.plans where key = 'package_test_b'
  ) then
    raise exception 'Tenant B plan isolation failed';
  end if;
  if exists (
    select 1 from public.tenant_limit_overrides
    where tenant_id = '00000000-0000-4000-8000-000000000311'
  ) then
    raise exception 'Cross-tenant override read unexpectedly succeeded';
  end if;
end
$test$;

rollback;
