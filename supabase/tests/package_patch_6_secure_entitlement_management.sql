-- Run against a disposable/local database after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/package_patch_6_secure_entitlement_management.sql
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000361',
   'authenticated', 'authenticated', 'tenant-a-p6@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000362',
   'authenticated', 'authenticated', 'tenant-b-p6@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000361',
   'Package 6 Tenant A', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000362',
   'Package 6 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000361',
   '00000000-0000-4000-8000-000000000361',
   'Package 6 Owner A', 'tenant-a-p6@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000362',
   '00000000-0000-4000-8000-000000000362',
   'Package 6 Owner B', 'tenant-b-p6@example.invalid', 'owner');

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);

do $test$
declare
  v_plan_id uuid;
  v_replacement_plan_id uuid;
  v_inactive_plan_id uuid;
  v_feature_id uuid;
  v_subscription_id uuid;
  v_audit_count_before bigint;
begin
  select count(*) into v_audit_count_before
  from public.entitlement_audit_logs;

  v_plan_id := public.platform_upsert_plan(
    null, 'package_patch_6_plan', 'Package 6 Plan', 'Test plan'
  );
  v_plan_id := public.platform_upsert_plan(
    v_plan_id, 'package_patch_6_plan', 'Package 6 Plan Updated', 'Updated plan'
  );
  v_feature_id := public.platform_upsert_feature(
    null, 'reports.package_patch_6', 'reports', 'Package 6 Reports', 'Test feature'
  );

  perform public.platform_set_plan_feature(
    v_plan_id, v_feature_id, false, 'Default disabled'
  );
  perform public.platform_set_plan_limit(
    v_plan_id, 'reports.history_days', 30, 'Default limit'
  );
  perform public.platform_set_plan_feature(
    v_plan_id, v_feature_id, true, 'Enable feature'
  );
  perform public.platform_set_plan_limit(
    v_plan_id, 'reports.history_days', 365, 'Increase limit'
  );

  perform public.platform_set_feature_active(v_feature_id, false);
  begin
    perform public.platform_set_plan_feature(
      v_plan_id, v_feature_id, true, 'Must fail while inactive'
    );
    raise exception 'Inactive feature was assigned unexpectedly';
  exception when invalid_parameter_value then null;
  end;
  perform public.platform_set_feature_active(v_feature_id, true);

  v_subscription_id := public.platform_set_tenant_subscription(
    '00000000-0000-4000-8000-000000000361',
    v_plan_id,
    'active',
    'Test subscription'
  );
  if v_subscription_id is null then
    raise exception 'Trusted subscription assignment failed';
  end if;

  v_replacement_plan_id := public.platform_upsert_plan(
    null, 'package_patch_6_replacement', 'Package 6 Replacement', null
  );
  perform public.platform_set_tenant_subscription(
    '00000000-0000-4000-8000-000000000361',
    v_replacement_plan_id,
    'active',
    'Change subscription'
  );
  perform public.platform_set_tenant_subscription(
    '00000000-0000-4000-8000-000000000361',
    v_plan_id,
    'active',
    'Restore test plan'
  );
  if (select count(*) from public.tenant_subscriptions
      where tenant_id = '00000000-0000-4000-8000-000000000361'
        and is_active and deleted_at is null) <> 1 then
    raise exception 'Subscription change produced duplicate active rows';
  end if;

  perform public.platform_set_tenant_feature_override(
    '00000000-0000-4000-8000-000000000361',
    v_feature_id,
    false,
    'Tenant override wins'
  );
  perform public.platform_set_tenant_limit_override(
    '00000000-0000-4000-8000-000000000361',
    'reports.history_days',
    90,
    'Tenant limit wins'
  );

  if not exists (
    select 1 from public.plans
    where id = v_plan_id and name = 'Package 6 Plan Updated' and is_active
  ) or not exists (
    select 1 from public.plan_features
    where plan_id = v_plan_id and feature_id = v_feature_id and enabled
  ) then
    raise exception 'Trusted plan/feature changes did not persist';
  end if;

  if (select value from public.plan_limits
      where plan_id = v_plan_id and key = 'reports.history_days') <> 365 then
    raise exception 'Trusted plan limit change did not persist';
  end if;

  if (select enabled from public.tenant_feature_overrides
      where tenant_id = '00000000-0000-4000-8000-000000000361'
        and feature_id = v_feature_id and is_active) is distinct from false then
    raise exception 'Tenant feature override did not take priority';
  end if;
  if (select value from public.tenant_limit_overrides
      where tenant_id = '00000000-0000-4000-8000-000000000361'
        and key = 'reports.history_days' and is_active) <> 90 then
    raise exception 'Tenant limit override did not take priority';
  end if;

  if (select count(*) from public.entitlement_audit_logs) <
       v_audit_count_before + 9 then
    raise exception 'Entitlement changes were not fully audited';
  end if;

  v_inactive_plan_id := public.platform_upsert_plan(
    null, 'package_patch_6_inactive', 'Inactive Test Plan', null
  );
  perform public.platform_set_plan_active(v_inactive_plan_id, false);
  begin
    perform public.platform_set_tenant_subscription(
      '00000000-0000-4000-8000-000000000362',
      v_inactive_plan_id,
      'active',
      'Must fail'
    );
    raise exception 'Inactive plan was assigned unexpectedly';
  exception when invalid_parameter_value then null;
  end;

  perform public.platform_remove_tenant_feature_override(
    '00000000-0000-4000-8000-000000000361', v_feature_id, 'Remove override'
  );
  perform public.platform_remove_tenant_limit_override(
    '00000000-0000-4000-8000-000000000361',
    'reports.history_days',
    'Remove override'
  );
end
$test$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000362',
  true
);

do $test$
begin
  begin
    perform public.platform_set_tenant_limit_override(
      '00000000-0000-4000-8000-000000000361',
      'reports.history_days',
      999,
      'Cross-tenant attempt'
    );
    raise exception 'Authenticated cross-tenant RPC unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.plans set name = 'Client mutation';
    raise exception 'Authenticated entitlement table update unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  begin
    delete from public.tenant_feature_overrides;
    raise exception 'Authenticated override delete unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end
$test$;

rollback;
