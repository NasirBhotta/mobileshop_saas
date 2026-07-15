-- Run after all migrations against a disposable/local database.
begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000401',
   'authenticated', 'authenticated', 'admin-p2@example.invalid', '', now(), '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000402',
   'authenticated', 'authenticated', 'user-p2@example.invalid', '', now(), '{}', '{}', now(), now(), '', '', '', '');

insert into public.platform_admins (user_id) values ('00000000-0000-4000-8000-000000000401');
insert into public.tenants (id, shop_name, business_type, branch_count, plan, status, setup_complete) values
  ('00000000-0000-4000-8000-000000000403', 'Patch 2 Starter', 'retail', 2, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000404', 'Patch 2 Business', 'retail', 1, 'business', 'suspended', true),
  ('00000000-0000-4000-8000-000000000405', 'Patch 2 Enterprise', 'retail', 3, 'enterprise', 'active', true);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000401', true);

do $test$
declare summary record; detail record;
begin
  select * into summary from public.platform_tenant_summary();
  if summary.total_tenants < 3 or summary.starter_tenants < 1
     or summary.business_tenants < 1 or summary.enterprise_tenants < 1 then
    raise exception 'Tenant summary is incomplete';
  end if;

  if (select count(*) from public.platform_list_tenants('Patch 2', 'active', null)) <> 2 then
    raise exception 'Tenant search/status filter failed';
  end if;
  if (select count(*) from public.platform_list_tenants(null, null, 'business')) <> 1 then
    raise exception 'Tenant plan filter failed';
  end if;

  select * into detail from public.platform_get_tenant('00000000-0000-4000-8000-000000000403');
  if detail.shop_name <> 'Patch 2 Starter' or detail.branch_count <> 2 then
    raise exception 'Tenant detail failed';
  end if;

  perform public.platform_set_tenant_status('00000000-0000-4000-8000-000000000403', 'suspended', 'Patch test');
  if (select status from public.platform_get_tenant('00000000-0000-4000-8000-000000000403')) <> 'suspended' then
    raise exception 'Tenant suspension failed';
  end if;
end
$test$;

-- Audit logs are intentionally not directly readable by authenticated clients.
-- Verify the server-side audit as the privileged test runner instead of
-- weakening production grants for this assertion.
reset role;

do $test$
begin
  if not exists (
    select 1
    from public.entitlement_audit_logs
    where tenant_id = '00000000-0000-4000-8000-000000000403'
      and action = 'tenant.status_changed'
  ) then
    raise exception 'Tenant status audit was not recorded';
  end if;
end
$test$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000401', true);
select public.platform_set_tenant_status(
  '00000000-0000-4000-8000-000000000403',
  'active',
  'Reactivate test'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000402', true);
do $test$
begin
  begin perform public.platform_tenant_summary(); raise exception 'Non-admin summary unexpectedly succeeded';
  exception when insufficient_privilege then if sqlstate <> '42501' then raise; end if; end;
  begin perform public.platform_set_tenant_status('00000000-0000-4000-8000-000000000403', 'suspended', null); raise exception 'Non-admin status update unexpectedly succeeded';
  exception when insufficient_privilege then if sqlstate <> '42501' then raise; end if; end;
end
$test$;

rollback;
