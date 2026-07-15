-- Admin Portal Patch 1: single-role platform admin foundation.

create table public.platform_admins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  admin_type text not null default 'platform_admin'
    check (admin_type = 'platform_admin'),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index platform_admins_active_user_idx
on public.platform_admins (user_id)
where is_active;

alter table public.platform_admins enable row level security;

create policy "platform admins read own membership"
on public.platform_admins for select to authenticated
using (user_id = auth.uid());

create or replace function public.is_active_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = auth.uid()
      and pa.admin_type = 'platform_admin'
      and pa.is_active
  )
$function$;

revoke all on table public.platform_admins from anon, authenticated;
grant select on table public.platform_admins to authenticated;
grant all privileges on table public.platform_admins to service_role;

revoke all on function public.is_active_platform_admin() from public;
revoke all on function public.is_active_platform_admin() from anon;
grant execute on function public.is_active_platform_admin() to authenticated;
grant execute on function public.is_active_platform_admin() to service_role;
