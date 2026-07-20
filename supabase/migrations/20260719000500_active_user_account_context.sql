-- Make account revocation explicit and let clients distinguish a missing or
-- disabled profile from an RLS-hidden row.

alter table public.users
  add column if not exists is_active boolean not null default true,
  add column if not exists deleted_at timestamptz;

alter table public.users
  drop constraint if exists users_deleted_inactive_check;
alter table public.users
  add constraint users_deleted_inactive_check
  check (deleted_at is null or is_active = false);

create index if not exists users_active_tenant_idx
on public.users (tenant_id, is_active)
where deleted_at is null;

drop policy if exists "users_select_own_profile" on public.users;
create policy "users_select_own_profile"
on public.users
for select
to authenticated
using (
  id = auth.uid()
  and is_active = true
  and deleted_at is null
);

drop policy if exists "users_insert_own_profile" on public.users;
create policy "users_insert_own_profile"
on public.users
for insert
to authenticated
with check (
  id = auth.uid()
  and role = 'owner'
  and tenant_id is null
  and branch_id is null
  and approval_pin is null
  and is_active = true
  and deleted_at is null
);

drop policy if exists "users_update_own_setup_fields" on public.users;
create policy "users_update_own_setup_fields"
on public.users
for update
to authenticated
using (
  id = auth.uid()
  and is_active = true
  and deleted_at is null
)
with check (
  id = auth.uid()
  and is_active = true
  and deleted_at is null
);

create or replace function public.current_account_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  account public.users%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select u.*
  into account
  from public.users u
  where u.id = auth.uid();

  if not found then
    return jsonb_build_object(
      'exists', false,
      'is_active', false
    );
  end if;

  return jsonb_build_object(
    'exists', true,
    'is_active', account.is_active and account.deleted_at is null,
    'id', account.id,
    'tenant_id', account.tenant_id,
    'branch_id', account.branch_id,
    'full_name', account.full_name,
    'email', account.email,
    'phone', account.phone,
    'role', account.role,
    'deleted_at', account.deleted_at
  );
end
$function$;

revoke all on function public.current_account_context() from public, anon;
grant execute on function public.current_account_context()
to authenticated, service_role;
