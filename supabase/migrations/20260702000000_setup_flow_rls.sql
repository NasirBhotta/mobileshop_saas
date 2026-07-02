alter table public.users enable row level security;
alter table public.tenants enable row level security;
alter table public.branches enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'users'
      and policyname = 'users_select_own_profile'
  ) then
    create policy "users_select_own_profile"
      on public.users
      for select
      to authenticated
      using (id = auth.uid());
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'users'
      and policyname = 'users_insert_own_profile'
  ) then
    create policy "users_insert_own_profile"
      on public.users
      for insert
      to authenticated
      with check (
        id = auth.uid()
        and coalesce(role, 'owner') = 'owner'
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'users'
      and policyname = 'users_update_own_setup_fields'
  ) then
    create policy "users_update_own_setup_fields"
      on public.users
      for update
      to authenticated
      using (id = auth.uid())
      with check (
        id = auth.uid()
        and (
          tenant_id is null
          or tenant_id = auth.uid()
          or (
            branch_id is not null
            and exists (
              select 1
              from public.branches b
              where b.id = branch_id
                and b.tenant_id = tenant_id
            )
          )
        )
        and (
          branch_id is null
          or exists (
            select 1
            from public.branches b
            where b.id = branch_id
              and b.tenant_id = tenant_id
          )
        )
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'tenants'
      and policyname = 'tenants_insert_during_own_setup'
  ) then
    create policy "tenants_insert_during_own_setup"
      on public.tenants
      for insert
      to authenticated
      with check (
        id = auth.uid()
        and setup_complete = false
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'tenants'
      and policyname = 'tenants_select_own_tenant'
  ) then
    create policy "tenants_select_own_tenant"
      on public.tenants
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.users u
          where u.id = auth.uid()
            and u.tenant_id = tenants.id
        )
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'tenants'
      and policyname = 'tenants_update_owned_tenant'
  ) then
    create policy "tenants_update_owned_tenant"
      on public.tenants
      for update
      to authenticated
      using (
        exists (
          select 1
          from public.users u
          where u.id = auth.uid()
            and u.tenant_id = tenants.id
            and u.role = 'owner'
        )
      )
      with check (
        exists (
          select 1
          from public.users u
          where u.id = auth.uid()
            and u.tenant_id = tenants.id
            and u.role = 'owner'
        )
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'branches'
      and policyname = 'branches_select_own_tenant'
  ) then
    create policy "branches_select_own_tenant"
      on public.branches
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.users u
          where u.id = auth.uid()
            and u.tenant_id = branches.tenant_id
        )
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'branches'
      and policyname = 'branches_insert_owned_tenant'
  ) then
    create policy "branches_insert_owned_tenant"
      on public.branches
      for insert
      to authenticated
      with check (
        exists (
          select 1
          from public.users u
          where u.id = auth.uid()
            and u.tenant_id = branches.tenant_id
            and u.role = 'owner'
        )
      );
  end if;
end $$;
