-- Run against a disposable/local database after applying all migrations:
-- psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--   -f supabase/tests/security_patch_9_expense_policy_dedup.sql

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, email_change,
  email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000091',
   'authenticated', 'authenticated', 'owner-a9@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000',
   '00000000-0000-4000-8000-000000000092',
   'authenticated', 'authenticated', 'owner-b9@example.invalid', '', now(),
   '{}', '{}', now(), now(), '', '', '', '');

insert into public.tenants (
  id, shop_name, business_type, branch_count, plan, status, setup_complete
) values
  ('00000000-0000-4000-8000-000000000091',
   'Patch 9 Tenant A', 'retail', 1, 'starter', 'active', true),
  ('00000000-0000-4000-8000-000000000092',
   'Patch 9 Tenant B', 'retail', 1, 'starter', 'active', true);

insert into public.users (id, tenant_id, full_name, email, role) values
  ('00000000-0000-4000-8000-000000000091',
   '00000000-0000-4000-8000-000000000091',
   'Patch 9 Owner A', 'owner-a9@example.invalid', 'owner'),
  ('00000000-0000-4000-8000-000000000092',
   '00000000-0000-4000-8000-000000000092',
   'Patch 9 Owner B', 'owner-b9@example.invalid', 'owner');

insert into public.branches (id, tenant_id, name, address, city, is_active) values
  ('00000000-0000-4000-8000-000000000093',
   '00000000-0000-4000-8000-000000000091',
   'Tenant A Branch', 'A address', 'A city', true),
  ('00000000-0000-4000-8000-000000000094',
   '00000000-0000-4000-8000-000000000092',
   'Tenant B Branch', 'B address', 'B city', true);

-- Cross-tenant rows prove isolation rather than merely testing an empty result.
insert into public.expense_categories (
  id, tenant_id, branch_id, name, is_active, created_by
) values (
  '00000000-0000-4000-8000-000000000096',
  '00000000-0000-4000-8000-000000000092',
  '00000000-0000-4000-8000-000000000094',
  'Tenant B Category', true,
  '00000000-0000-4000-8000-000000000092'
);

insert into public.recurring_expense_rules (
  id, tenant_id, branch_id, category_id, category_name, title,
  estimated_amount, payment_mode, frequency, interval_count,
  start_date, next_due_date, status, created_by
) values (
  '00000000-0000-4000-8000-000000000098',
  '00000000-0000-4000-8000-000000000092',
  '00000000-0000-4000-8000-000000000094',
  '00000000-0000-4000-8000-000000000096',
  'Tenant B Category', 'Tenant B Recurring', 100, 'cash', 'monthly', 1,
  current_date, current_date, 'active',
  '00000000-0000-4000-8000-000000000092'
);

insert into public.expenses (
  id, tenant_id, branch_id, category_id, category_name, title,
  expense_date, amount, payment_mode, status, source, created_by
) values (
  '00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000092',
  '00000000-0000-4000-8000-000000000094',
  '00000000-0000-4000-8000-000000000096',
  'Tenant B Category', 'Tenant B Expense', current_date, 50,
  'cash', 'draft', 'manual',
  '00000000-0000-4000-8000-000000000092'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000091',
  true
);

-- CRUD through the surviving policies.
insert into public.expense_categories (
  id, tenant_id, branch_id, name, is_active, created_by
) values (
  '00000000-0000-4000-8000-000000000095',
  '00000000-0000-4000-8000-000000000091',
  '00000000-0000-4000-8000-000000000093',
  'Tenant A Category', true, auth.uid()
);

insert into public.recurring_expense_rules (
  id, tenant_id, branch_id, category_id, category_name, title,
  estimated_amount, payment_mode, frequency, interval_count,
  start_date, next_due_date, status, created_by
) values (
  '00000000-0000-4000-8000-000000000097',
  '00000000-0000-4000-8000-000000000091',
  '00000000-0000-4000-8000-000000000093',
  '00000000-0000-4000-8000-000000000095',
  'Tenant A Category', 'Tenant A Recurring', 100, 'cash', 'monthly', 1,
  current_date, current_date, 'active', auth.uid()
);

insert into public.expenses (
  id, tenant_id, branch_id, category_id, category_name, title,
  expense_date, amount, payment_mode, status, source, created_by
) values (
  '00000000-0000-4000-8000-000000000099',
  '00000000-0000-4000-8000-000000000091',
  '00000000-0000-4000-8000-000000000093',
  '00000000-0000-4000-8000-000000000095',
  'Tenant A Category', 'Tenant A Expense', current_date, 50,
  'cash', 'draft', 'manual', auth.uid()
);

update public.expense_categories
set name = 'Tenant A Category Updated'
where id = '00000000-0000-4000-8000-000000000095';

update public.recurring_expense_rules
set title = 'Tenant A Recurring Updated'
where id = '00000000-0000-4000-8000-000000000097';

update public.expenses
set title = 'Tenant A Expense Updated'
where id = '00000000-0000-4000-8000-000000000099';

do $test$
declare
  row_count_value integer;
  policy_count integer;
  target_table text;
begin
  foreach target_table in array array[
    'expense_categories', 'expenses', 'recurring_expense_rules'
  ] loop
    select count(*) into policy_count
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = target_table
      and cmd = 'ALL'
      and permissive = 'PERMISSIVE';

    if policy_count <> 1 then
      raise exception 'public.% has % permissive ALL policies; expected 1',
        target_table, policy_count;
    end if;
  end loop;

  select count(*) into row_count_value from public.expense_categories;
  if row_count_value <> 1 then
    raise exception 'Expense category tenant isolation changed';
  end if;

  select count(*) into row_count_value from public.recurring_expense_rules;
  if row_count_value <> 1 then
    raise exception 'Recurring expense tenant isolation changed';
  end if;

  select count(*) into row_count_value from public.expenses;
  if row_count_value <> 1 then
    raise exception 'Expense tenant isolation changed';
  end if;

  if not exists (
    select 1 from public.expense_categories
    where id = '00000000-0000-4000-8000-000000000095'
      and name = 'Tenant A Category Updated'
  ) then
    raise exception 'Expense category UPDATE behaviour changed';
  end if;

  if not exists (
    select 1 from public.recurring_expense_rules
    where id = '00000000-0000-4000-8000-000000000097'
      and title = 'Tenant A Recurring Updated'
  ) then
    raise exception 'Recurring expense UPDATE behaviour changed';
  end if;

  if not exists (
    select 1 from public.expenses
    where id = '00000000-0000-4000-8000-000000000099'
      and title = 'Tenant A Expense Updated'
  ) then
    raise exception 'Expense UPDATE behaviour changed';
  end if;

  update public.expenses set title = 'Cross tenant update'
  where id = '00000000-0000-4000-8000-000000000100';
  get diagnostics row_count_value = row_count;
  if row_count_value <> 0 then
    raise exception 'Cross-tenant expense update unexpectedly succeeded';
  end if;

  begin
    insert into public.expense_categories (
      tenant_id, branch_id, name, created_by
    ) values (
      '00000000-0000-4000-8000-000000000092',
      '00000000-0000-4000-8000-000000000094',
      'Cross tenant category', auth.uid()
    );
    raise exception 'Cross-tenant expense insert unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlstate <> '42501' then raise; end if;
  end;
end
$test$;

do $test$
declare deleted_count integer;
begin
  delete from public.expenses
  where id = '00000000-0000-4000-8000-000000000099';
  get diagnostics deleted_count = row_count;
  if deleted_count <> 1 then
    raise exception 'Expense DELETE behaviour changed';
  end if;

  delete from public.recurring_expense_rules
  where id = '00000000-0000-4000-8000-000000000097';
  get diagnostics deleted_count = row_count;
  if deleted_count <> 1 then
    raise exception 'Recurring expense DELETE behaviour changed';
  end if;

  delete from public.expense_categories
  where id = '00000000-0000-4000-8000-000000000095';
  get diagnostics deleted_count = row_count;
  if deleted_count <> 1 then
    raise exception 'Expense category DELETE behaviour changed';
  end if;
end
$test$;

rollback;
