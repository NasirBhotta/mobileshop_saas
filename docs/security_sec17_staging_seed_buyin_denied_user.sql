-- SEC-17 staging-only fixture for an unauthorized buy-in caller.
-- Prerequisite: create and auto-confirm this STAGING Auth user first:
--   sec17.denied@gmail.com
-- It deliberately creates no role or branch-role permission assignment.

begin;

do $fixture$
declare
  v_user_id uuid;
begin
  select id into v_user_id
  from auth.users
  where email = 'sec17.denied@gmail.com'
  limit 1;

  if v_user_id is null then
    raise exception using
      errcode = '22023',
      message = 'Create and auto-confirm sec17.denied@gmail.com in STAGING Auth first.';
  end if;

  insert into public.users (
    id, tenant_id, branch_id, full_name, email, role, is_active, deleted_at
  ) values (
    v_user_id,
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'SEC-17 Denied Test User', 'sec17.denied@gmail.com', 'cashier', true, null
  )
  on conflict (id) do update
  set tenant_id = excluded.tenant_id,
      branch_id = excluded.branch_id,
      full_name = excluded.full_name,
      email = excluded.email,
      role = 'cashier',
      is_active = true,
      deleted_at = null;

  delete from public.user_role_assignments
  where user_id = v_user_id;

  delete from public.user_branch_role_assignments
  where user_id = v_user_id;
end;
$fixture$;

commit;

select id, email, role, is_active, tenant_id, branch_id
from public.users
where email = 'sec17.denied@gmail.com';
