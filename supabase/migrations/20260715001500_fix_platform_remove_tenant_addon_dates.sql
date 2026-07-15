-- Patch 6 repair: immediate removal must still satisfy expires_at > starts_at.
-- now() is transaction-stable, so an assignment created and removed in the
-- same transaction can otherwise receive identical timestamps.

create or replace function public.platform_remove_tenant_addon(
  p_assignment_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  row_before public.tenant_addons%rowtype;
begin
  perform public.require_active_platform_admin();

  select * into row_before
  from public.tenant_addons
  where id = p_assignment_id
  for update;

  if row_before.id is null then
    raise exception using errcode = 'P0002', message = 'Assignment not found.';
  end if;

  update public.tenant_addons
  set enabled = false,
      status = 'removed',
      expires_at = case
        when expires_at is null or expires_at > clock_timestamp()
          then greatest(clock_timestamp(), starts_at + interval '1 microsecond')
        else expires_at
      end
  where id = p_assignment_id;

  insert into public.entitlement_audit_logs (
    tenant_id, action, entity_type, entity_id, reason,
    previous_value, new_value
  ) values (
    row_before.tenant_id,
    'addon.removed',
    'tenant_addon',
    row_before.id,
    nullif(trim(p_reason), ''),
    to_jsonb(row_before),
    jsonb_build_object('status', 'removed')
  );
end
$function$;

revoke all on function public.platform_remove_tenant_addon(uuid, text)
from public, anon;
grant execute on function public.platform_remove_tenant_addon(uuid, text)
to authenticated, service_role;
