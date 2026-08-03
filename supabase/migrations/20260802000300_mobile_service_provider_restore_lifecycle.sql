-- Restore a provider configuration without creating a duplicate provider row.
-- The linked wallet is part of the provider lifecycle and is reactivated in
-- the same transaction, preserving its balance and immutable ledger history.

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
    raise exception using errcode = '22023', message = 'Unsupported provider.';
  end if;
  if v_name = '' then
    raise exception using errcode = '22023',
      message = 'Provider name is required.';
  end if;
  if not exists (
    select 1 from public.accounts account
    where account.id = p_provider_account_id
      and account.tenant_id = v_tenant_id
      and account.branch_id = p_branch_id
      and account.account_type = 'mobile_wallet'
      and account.is_active
  ) then
    raise exception using errcode = '22023',
      message = 'Select an active mobile-wallet account in this branch.';
  end if;

  insert into public.mobile_service_providers(
    id, tenant_id, branch_id, category, code, name,
    provider_account_id, is_active, created_by
  ) values (
    v_provider_id, v_tenant_id, p_branch_id, 'money_transfer', v_code,
    v_name, p_provider_account_id, true, auth.uid()
  )
  on conflict on constraint mobile_service_providers_code_unique do update
  set name = excluded.name,
      provider_account_id = excluded.provider_account_id,
      is_active = true,
      archived_at = null,
      archived_by = null,
      updated_at = now()
  returning mobile_service_providers.id into v_provider_id;

  return v_provider_id;
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
  v_wallet public.accounts%rowtype;
begin
  select provider.* into v_provider
  from public.mobile_service_providers provider
  where provider.id = p_provider_id
    and provider.tenant_id = v_tenant_id
  for update;

  if not found
     or not public.current_user_can_access_branch(v_provider.branch_id)
     or not public.current_user_has_permission(
       'mobile_service.settings.manage'
     ) then
    raise exception using errcode = '42501', message = 'Not allowed.';
  end if;

  select account.* into v_wallet
  from public.accounts account
  where account.id = v_provider.provider_account_id
    and account.tenant_id = v_provider.tenant_id
    and account.branch_id = v_provider.branch_id
    and account.account_type = 'mobile_wallet'
  for update;

  if not found then
    raise exception using errcode = '22023',
      message = 'Linked provider wallet is unavailable.';
  end if;

  update public.accounts
  set is_active = true,
      updated_at = now()
  where id = v_wallet.id
    and tenant_id = v_tenant_id
    and not is_active;

  update public.mobile_service_providers
  set is_active = true,
      archived_at = null,
      archived_by = null,
      updated_at = now()
  where id = p_provider_id
    and tenant_id = v_tenant_id;
end
$function$;

revoke all on function public.save_mobile_service_provider(
  uuid, uuid, text, text, uuid
) from public, anon;
revoke all on function public.restore_mobile_service_provider(uuid)
from public, anon;
grant execute on function public.save_mobile_service_provider(
  uuid, uuid, text, text, uuid
) to authenticated, service_role;
grant execute on function public.restore_mobile_service_provider(uuid)
to authenticated, service_role;
