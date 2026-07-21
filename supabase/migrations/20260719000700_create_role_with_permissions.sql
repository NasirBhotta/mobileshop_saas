-- Keep the existing role RPC intact while providing a safer owner-facing
-- operation that generates the internal code and saves permissions atomically.

create or replace function public.create_custom_role_with_permissions(
  p_name text,
  p_description text default null,
  p_permission_keys text[] default array[]::text[]
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  actor_tenant_id uuid := public.require_role_manager_tenant();
  base_code text;
  candidate_code text;
  suffix integer := 1;
begin
  p_name := trim(p_name);
  if p_name is null or length(p_name) = 0 then
    raise exception using errcode = '22023', message = 'Role name is required.';
  end if;

  base_code := trim(both '_' from regexp_replace(
    lower(p_name), '[^a-z0-9]+', '_', 'g'
  ));
  if base_code = '' or base_code !~ '^[a-z]' then
    base_code := 'role_' || base_code;
  end if;
  base_code := left(base_code, 40);
  if length(base_code) < 2 then
    base_code := 'role_' || base_code;
  end if;

  -- Serialize code allocation per tenant so concurrent role creation cannot
  -- race into the tenant/code unique index.
  perform pg_advisory_xact_lock(hashtextextended(actor_tenant_id::text, 0));

  candidate_code := base_code;
  while exists (
    select 1
    from public.roles r
    where r.tenant_id = actor_tenant_id
      and lower(r.code) = lower(candidate_code)
  ) loop
    suffix := suffix + 1;
    candidate_code := left(base_code, 40) || '_' || suffix::text;
  end loop;

  return public.create_custom_role(
    candidate_code,
    p_name,
    nullif(trim(p_description), ''),
    coalesce(p_permission_keys, array[]::text[])
  );
end
$function$;

revoke all on function public.create_custom_role_with_permissions(
  text, text, text[]
) from public, anon;
grant execute on function public.create_custom_role_with_permissions(
  text, text, text[]
) to authenticated;

