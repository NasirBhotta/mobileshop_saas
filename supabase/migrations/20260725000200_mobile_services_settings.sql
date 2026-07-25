-- Mobile service permission catalog and provider/rule management.

insert into public.permissions (
  key, module, action, name, description, is_active
)
values
  (
    'mobile_service.transaction.view', 'mobile_services', 'view',
    'View mobile service transactions',
    'View authorized-branch Easypaisa and JazzCash history.', true
  ),
  (
    'mobile_service.transaction.create', 'mobile_services', 'create',
    'Create mobile service transactions',
    'Record Easypaisa and JazzCash send/receive transactions.', true
  ),
  (
    'mobile_service.transaction.void', 'mobile_services', 'void',
    'Void mobile service transactions',
    'Reverse a completed mobile service transaction.', true
  ),
  (
    'mobile_service.settings.manage', 'mobile_services', 'manage',
    'Manage mobile service settings',
    'Configure providers, accounts, and charge rules.', true
  ),
  (
    'mobile_service.report.view', 'mobile_services', 'view',
    'View mobile service reports',
    'View mobile service totals, balances, and profit.', true
  )
on conflict (key) do update
set module = excluded.module,
    action = excluded.action,
    name = excluded.name,
    description = excluded.description,
    is_active = excluded.is_active;

-- Preserve the project's compatibility behaviour for system roles. Custom
-- roles can be configured normally from role management.
select public.sync_compatibility_role_permissions();

drop policy if exists "mobile service providers branch read"
on public.mobile_service_providers;
create policy "mobile service providers branch read"
on public.mobile_service_providers
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and public.current_user_can_access_branch(branch_id)
  and (
    public.current_user_has_permission('mobile_service.transaction.view')
    or public.current_user_has_permission('mobile_service.settings.manage')
  )
);

drop policy if exists "mobile service rules branch read"
on public.mobile_service_charge_rules;
create policy "mobile service rules branch read"
on public.mobile_service_charge_rules
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and public.current_user_can_access_branch(branch_id)
  and (
    public.current_user_has_permission('mobile_service.transaction.view')
    or public.current_user_has_permission('mobile_service.settings.manage') 
  )
);

drop policy if exists "mobile service transactions branch read"
on public.mobile_service_transactions;
create policy "mobile service transactions branch read"
on public.mobile_service_transactions
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and public.current_user_can_access_branch(branch_id)
  and (
    public.current_user_has_permission('mobile_service.transaction.view')
    or public.current_user_has_permission('mobile_service.transaction.create')
    or public.current_user_has_permission('mobile_service.report.view')
  )
);

create or replace function public.save_mobile_service_provider(
  p_provider_id uuid,
  p_branch_id uuid,
  p_code text,
  p_name text,
  p_provider_account_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_provider_id uuid := coalesce(p_provider_id, gen_random_uuid());
  v_code text := lower(trim(p_code));
  v_name text := trim(p_name);
begin
  if auth.uid() is null or v_tenant_id is null then
    raise exception using errcode = '42501',
      message = 'Authentication required.';
  end if;

  if not public.current_user_can_access_branch(p_branch_id)
     or not public.current_user_has_permission(
       'mobile_service.settings.manage'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  if v_code not in ('easypaisa', 'jazzcash') then
    raise exception using errcode = '22023',
      message = 'Unsupported provider.';
  end if;

  if v_name = '' then
    raise exception using errcode = '22023',
      message = 'Provider name is required.';
  end if;

  if not exists (
    select 1
    from public.accounts a
    where a.id = p_provider_account_id
      and a.tenant_id = v_tenant_id
      and a.branch_id = p_branch_id
      and a.is_active
      and a.account_type = 'mobile_wallet'
  ) then
    raise exception using errcode = '22023',
      message = 'Select an active mobile-wallet account in this branch.';
  end if;

  insert into public.mobile_service_providers (
    id, tenant_id, branch_id, category, code, name,
    provider_account_id, is_active, created_by
  )
  values (
    v_provider_id, v_tenant_id, p_branch_id, 'money_transfer',
    v_code, v_name, p_provider_account_id, true, auth.uid()
  )
  on conflict (id) do update
  set name = excluded.name,
      provider_account_id = excluded.provider_account_id
  where mobile_service_providers.tenant_id = v_tenant_id
    and mobile_service_providers.branch_id = p_branch_id
    and mobile_service_providers.is_active;

  if not found then
    raise exception using errcode = '42501',
      message = 'Provider was not found in the authorized branch.';
  end if;

  return v_provider_id;
end
$function$;

create or replace function public.save_mobile_service_charge_rule(
  p_rule_id uuid,
  p_provider_id uuid,
  p_operation text,
  p_calculation_method text,
  p_rate_amount numeric,
  p_per_amount numeric default null,
  p_minimum_fee numeric default null,
  p_maximum_fee numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_rule_id uuid := coalesce(p_rule_id, gen_random_uuid());
  v_provider public.mobile_service_providers%rowtype;
begin
  if auth.uid() is null or v_tenant_id is null then
    raise exception using errcode = '42501',
      message = 'Authentication required.';
  end if;

  select p.*
  into v_provider
  from public.mobile_service_providers p
  where p.id = p_provider_id
    and p.tenant_id = v_tenant_id
    and p.is_active;

  if not found
     or not public.current_user_can_access_branch(v_provider.branch_id)
     or not public.current_user_has_permission(
       'mobile_service.settings.manage'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  if p_operation not in ('send', 'receive') then
    raise exception using errcode = '22023',
      message = 'Unsupported operation.';
  end if;

  if p_calculation_method not in (
    'full_slab', 'proportional', 'fixed', 'manual'
  ) then
    raise exception using errcode = '22023',
      message = 'Unsupported calculation method.';
  end if;

  if coalesce(p_rate_amount, 0) < 0
     or p_minimum_fee < 0
     or p_maximum_fee < 0
     or (
       p_minimum_fee is not null
       and p_maximum_fee is not null
       and p_maximum_fee < p_minimum_fee
     )
     or (
       p_calculation_method in ('full_slab', 'proportional')
       and coalesce(p_per_amount, 0) <= 0
     ) then
    raise exception using errcode = '22023',
      message = 'Invalid charge-rule values.';
  end if;

  insert into public.mobile_service_charge_rules (
    id, tenant_id, branch_id, provider_id, operation,
    calculation_method, rate_amount, per_amount, minimum_fee,
    maximum_fee, is_active, created_by
  )
  values (
    v_rule_id, v_tenant_id, v_provider.branch_id, v_provider.id,
    p_operation, p_calculation_method, coalesce(p_rate_amount, 0),
    p_per_amount, p_minimum_fee, p_maximum_fee, true, auth.uid()
  )
  on conflict (id) do update
  set calculation_method = excluded.calculation_method,
      rate_amount = excluded.rate_amount,
      per_amount = excluded.per_amount,
      minimum_fee = excluded.minimum_fee,
      maximum_fee = excluded.maximum_fee
  where mobile_service_charge_rules.tenant_id = v_tenant_id
    and mobile_service_charge_rules.branch_id = v_provider.branch_id
    and mobile_service_charge_rules.provider_id = v_provider.id
    and mobile_service_charge_rules.operation = p_operation
    and mobile_service_charge_rules.is_active;

  if not found then
    raise exception using errcode = '42501',
      message = 'Rule was not found in the authorized branch.';
  end if;

  return v_rule_id;
end
$function$;

create or replace function public.archive_mobile_service_provider(
  p_provider_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_branch_id uuid;
begin
  select p.branch_id into v_branch_id
  from public.mobile_service_providers p
  where p.id = p_provider_id
    and p.tenant_id = v_tenant_id;

  if not found
     or not public.current_user_can_access_branch(v_branch_id)
     or not public.current_user_has_permission(
       'mobile_service.settings.manage'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  update public.mobile_service_charge_rules
  set is_active = false,
      archived_at = coalesce(archived_at, now()),
      archived_by = coalesce(archived_by, auth.uid())
  where provider_id = p_provider_id
    and tenant_id = v_tenant_id
    and is_active;

  update public.mobile_service_providers
  set is_active = false,
      archived_at = coalesce(archived_at, now()),
      archived_by = coalesce(archived_by, auth.uid())
  where id = p_provider_id
    and tenant_id = v_tenant_id
    and is_active;
end
$function$;

create or replace function public.archive_mobile_service_charge_rule(
  p_rule_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_branch_id uuid;
begin
  select r.branch_id into v_branch_id
  from public.mobile_service_charge_rules r
  where r.id = p_rule_id
    and r.tenant_id = v_tenant_id;

  if not found
     or not public.current_user_can_access_branch(v_branch_id)
     or not public.current_user_has_permission(
       'mobile_service.settings.manage'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  update public.mobile_service_charge_rules
  set is_active = false,
      archived_at = coalesce(archived_at, now()),
      archived_by = coalesce(archived_by, auth.uid())
  where id = p_rule_id
    and tenant_id = v_tenant_id
    and is_active;
end
$function$;

create or replace function public.restore_mobile_service_provider(
  p_provider_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_provider public.mobile_service_providers%rowtype;
begin
  select p.* into v_provider
  from public.mobile_service_providers p
  where p.id = p_provider_id
    and p.tenant_id = v_tenant_id;

  if not found
     or not public.current_user_can_access_branch(v_provider.branch_id)
     or not public.current_user_has_permission(
       'mobile_service.settings.manage'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  if not exists (
    select 1
    from public.accounts a
    where a.id = v_provider.provider_account_id
      and a.tenant_id = v_provider.tenant_id
      and a.branch_id = v_provider.branch_id
      and a.account_type = 'mobile_wallet'
      and a.is_active
  ) then
    raise exception using errcode = '22023',
      message = 'Provider wallet must be active before restoring provider.';
  end if;

  update public.mobile_service_providers
  set is_active = true,
      archived_at = null,
      archived_by = null
  where id = p_provider_id
    and tenant_id = v_tenant_id
    and not is_active;
end
$function$;

create or replace function public.restore_mobile_service_charge_rule(
  p_rule_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
  v_rule public.mobile_service_charge_rules%rowtype;
begin
  select r.* into v_rule
  from public.mobile_service_charge_rules r
  where r.id = p_rule_id
    and r.tenant_id = v_tenant_id;

  if not found
     or not public.current_user_can_access_branch(v_rule.branch_id)
     or not public.current_user_has_permission(
       'mobile_service.settings.manage'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  if not exists (
    select 1
    from public.mobile_service_providers p
    where p.id = v_rule.provider_id
      and p.tenant_id = v_rule.tenant_id
      and p.branch_id = v_rule.branch_id
      and p.is_active
  ) then
    raise exception using errcode = '22023',
      message = 'Restore the provider before restoring its rule.';
  end if;

  update public.mobile_service_charge_rules
  set is_active = true,
      archived_at = null,
      archived_by = null
  where id = p_rule_id
    and tenant_id = v_tenant_id
    and not is_active;
end
$function$;

revoke all on function public.save_mobile_service_provider(
  uuid, uuid, text, text, uuid
) from public, anon;
revoke all on function public.save_mobile_service_charge_rule(
  uuid, uuid, text, text, numeric, numeric, numeric, numeric
) from public, anon;
revoke all on function public.archive_mobile_service_provider(uuid)
from public, anon;
revoke all on function public.archive_mobile_service_charge_rule(uuid)
from public, anon;
revoke all on function public.restore_mobile_service_provider(uuid)
from public, anon;
revoke all on function public.restore_mobile_service_charge_rule(uuid)
from public, anon;

grant execute on function public.save_mobile_service_provider(
  uuid, uuid, text, text, uuid
) to authenticated;
grant execute on function public.save_mobile_service_charge_rule(
  uuid, uuid, text, text, numeric, numeric, numeric, numeric
) to authenticated;
grant execute on function public.archive_mobile_service_provider(uuid)
to authenticated;
grant execute on function public.archive_mobile_service_charge_rule(uuid)
to authenticated;
grant execute on function public.restore_mobile_service_provider(uuid)
to authenticated;
grant execute on function public.restore_mobile_service_charge_rule(uuid)
to authenticated;
