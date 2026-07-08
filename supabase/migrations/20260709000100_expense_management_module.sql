-- =========================================================
-- Module 6: Expense Management
-- FR-6.1.1 Expense.Entry.Standard
-- FR-6.1.2 Expense.Entry.Recurring
-- FR-6.2.1 Expense.Report.View
-- FR-6.2.2 Expense.Report.ProfitIntegration
-- =========================================================

-- ---------------------------------------------------------
-- Helper: current user's tenant
-- Safe to redefine because procurement module may already have it.
-- ---------------------------------------------------------
create or replace function public.current_user_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select u.tenant_id
  from public.users u
  where u.id = auth.uid()
  limit 1
$$;

-- ---------------------------------------------------------
-- Storage bucket for optional expense receipts
-- Path convention:
-- expense-receipts/{tenant_id}/{expense_id}/{filename}
-- ---------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('expense-receipts', 'expense-receipts', false)
on conflict (id) do nothing;

-- ---------------------------------------------------------
-- Expense Categories
-- ---------------------------------------------------------
create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists expense_categories_unique_name_per_tenant
on public.expense_categories (tenant_id, lower(name));

create index if not exists idx_expense_categories_tenant
on public.expense_categories(tenant_id);

-- ---------------------------------------------------------
-- Expenses
-- status:
-- draft      = recurring auto-generated, pending confirmation
-- confirmed  = actual expense confirmed
-- cancelled  = ignored/cancelled
-- ---------------------------------------------------------
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,

  expense_date date not null,
  due_date date,

  category_id uuid references public.expense_categories(id) on delete set null,
  category_name text not null,

  amount numeric not null default 0 check (amount >= 0),
  payment_mode text not null default 'cash',

  note text,

  receipt_url text,
  receipt_storage_path text,

  status text not null default 'confirmed'
    check (status in ('draft', 'confirmed', 'cancelled')),

  recurring_rule_id uuid,
  is_recurring_generated boolean not null default false,

  created_by uuid references auth.users(id),
  confirmed_at timestamptz,
  cancelled_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_expenses_tenant
on public.expenses(tenant_id);

create index if not exists idx_expenses_branch_date
on public.expenses(branch_id, expense_date desc);

create index if not exists idx_expenses_category
on public.expenses(category_id);

create index if not exists idx_expenses_status
on public.expenses(status);

create index if not exists idx_expenses_recurring_rule
on public.expenses(recurring_rule_id);

-- one generated draft per recurring rule per due date
create unique index if not exists expenses_unique_generated_recurring_due
on public.expenses(tenant_id, recurring_rule_id, due_date)
where recurring_rule_id is not null
and is_recurring_generated = true;

-- ---------------------------------------------------------
-- Recurring Expense Rules
-- frequency:
-- daily, weekly, monthly, yearly
-- Auto generated expenses are created as draft.
-- ---------------------------------------------------------
create table if not exists public.recurring_expense_rules (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,

  category_id uuid references public.expense_categories(id) on delete set null,
  category_name text not null,

  estimated_amount numeric not null default 0 check (estimated_amount >= 0),
  payment_mode text not null default 'cash',
  note text,

  frequency text not null default 'monthly'
    check (frequency in ('daily', 'weekly', 'monthly', 'yearly')),

  interval_count int not null default 1 check (interval_count > 0),

  start_date date not null,
  end_date date,
  next_due_date date not null,

  reminder_days_before int not null default 3 check (reminder_days_before >= 0),

  status text not null default 'active'
    check (status in ('active', 'paused', 'cancelled')),

  created_by uuid references auth.users(id),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_recurring_expense_rules_tenant
on public.recurring_expense_rules(tenant_id);

create index if not exists idx_recurring_expense_rules_branch
on public.recurring_expense_rules(branch_id);

create index if not exists idx_recurring_expense_rules_next_due
on public.recurring_expense_rules(next_due_date);

create index if not exists idx_recurring_expense_rules_status
on public.recurring_expense_rules(status);

alter table public.expenses
drop constraint if exists expenses_recurring_rule_id_fkey;

alter table public.expenses
add constraint expenses_recurring_rule_id_fkey
foreign key (recurring_rule_id)
references public.recurring_expense_rules(id)
on delete set null;

-- ---------------------------------------------------------
-- Updated at trigger
-- ---------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_expense_categories_updated_at on public.expense_categories;
create trigger trg_expense_categories_updated_at
before update on public.expense_categories
for each row
execute function public.set_updated_at();

drop trigger if exists trg_expenses_updated_at on public.expenses;
create trigger trg_expenses_updated_at
before update on public.expenses
for each row
execute function public.set_updated_at();

drop trigger if exists trg_recurring_expense_rules_updated_at on public.recurring_expense_rules;
create trigger trg_recurring_expense_rules_updated_at
before update on public.recurring_expense_rules
for each row
execute function public.set_updated_at();

-- ---------------------------------------------------------
-- Recurring due date calculator
-- ---------------------------------------------------------
create or replace function public.advance_recurring_due_date(
  p_due_date date,
  p_frequency text,
  p_interval_count int
)
returns date
language plpgsql
immutable
as $$
begin
  if p_frequency = 'daily' then
    return p_due_date + (p_interval_count || ' days')::interval;
  elsif p_frequency = 'weekly' then
    return p_due_date + ((p_interval_count * 7) || ' days')::interval;
  elsif p_frequency = 'monthly' then
    return p_due_date + (p_interval_count || ' months')::interval;
  elsif p_frequency = 'yearly' then
    return p_due_date + (p_interval_count || ' years')::interval;
  end if;

  return p_due_date + interval '1 month';
end;
$$;

-- ---------------------------------------------------------
-- RPC: Generate recurring expense drafts
-- App should call this during expense screen load/sync.
-- It creates draft entries up to p_until_date.
-- ---------------------------------------------------------
create or replace function public.generate_recurring_expense_entries(
  p_until_date date default (current_date + interval '30 days')::date
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_rule record;
  v_due date;
  v_created_count int := 0;
begin
  v_tenant_id := public.current_user_tenant_id();

  if v_tenant_id is null then
    raise exception 'User tenant not found';
  end if;

  for v_rule in
    select *
    from public.recurring_expense_rules
    where tenant_id = v_tenant_id
      and status = 'active'
      and next_due_date <= p_until_date
      and (end_date is null or next_due_date <= end_date)
  loop
    v_due := v_rule.next_due_date;

    while v_due <= p_until_date
      and (v_rule.end_date is null or v_due <= v_rule.end_date)
    loop
      insert into public.expenses (
        tenant_id,
        branch_id,
        expense_date,
        due_date,
        category_id,
        category_name,
        amount,
        payment_mode,
        note,
        status,
        recurring_rule_id,
        is_recurring_generated,
        created_by
      )
      values (
        v_rule.tenant_id,
        v_rule.branch_id,
        v_due,
        v_due,
        v_rule.category_id,
        v_rule.category_name,
        v_rule.estimated_amount,
        v_rule.payment_mode,
        v_rule.note,
        'draft',
        v_rule.id,
        true,
        auth.uid()
      )
      on conflict do nothing;

      if found then
        v_created_count := v_created_count + 1;
      end if;

      v_due := public.advance_recurring_due_date(
        v_due,
        v_rule.frequency,
        v_rule.interval_count
      );
    end loop;

    update public.recurring_expense_rules
    set next_due_date = v_due
    where id = v_rule.id
      and tenant_id = v_tenant_id;
  end loop;

  return v_created_count;
end;
$$;

-- ---------------------------------------------------------
-- RPC: Confirm draft expense
-- Actual amount can differ from estimated recurring amount.
-- ---------------------------------------------------------
create or replace function public.confirm_expense(
  p_expense_id uuid,
  p_actual_amount numeric,
  p_payment_mode text default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.current_user_tenant_id();

  if v_tenant_id is null then
    raise exception 'User tenant not found';
  end if;

  if p_actual_amount < 0 then
    raise exception 'Expense amount must be 0 or greater';
  end if;

  update public.expenses
  set
    amount = p_actual_amount,
    payment_mode = coalesce(p_payment_mode, payment_mode),
    note = coalesce(p_note, note),
    status = 'confirmed',
    confirmed_at = now()
  where id = p_expense_id
    and tenant_id = v_tenant_id;

  if not found then
    raise exception 'Expense not found or not allowed';
  end if;

  return p_expense_id;
end;
$$;

-- ---------------------------------------------------------
-- Report access rule:
-- starter    = last 30 days only
-- business   = up to 1 year
-- enterprise = unlimited
-- ---------------------------------------------------------
create or replace function public.validate_expense_report_range(
  p_tenant_id uuid,
  p_start_date date,
  p_end_date date
)
returns void
language plpgsql
stable
as $$
declare
  v_plan text;
begin
  select plan into v_plan
  from public.tenants
  where id = p_tenant_id;

  v_plan := coalesce(v_plan, 'starter');

  if p_start_date is null or p_end_date is null then
    raise exception 'Start date and end date are required';
  end if;

  if p_end_date < p_start_date then
    raise exception 'End date cannot be before start date';
  end if;

  if v_plan = 'starter' then
    if p_start_date < current_date - interval '30 days' then
      raise exception 'Starter plan can view last 30 days only';
    end if;
  elsif v_plan = 'business' then
    if p_start_date < p_end_date - interval '1 year' then
      raise exception 'Business plan can view reports up to 1 year only';
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------
-- RPC: Expense report
-- Branch hierarchy:
-- p_branch_id null = all branches in tenant
-- p_branch_id set  = selected branch only
-- ---------------------------------------------------------
create or replace function public.expense_report(
  p_start_date date,
  p_end_date date,
  p_branch_id uuid default null,
  p_category_id uuid default null,
  p_category_name text default null
)
returns table (
  category_id uuid,
  category_name text,
  total_amount numeric,
  entry_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.current_user_tenant_id();

  if v_tenant_id is null then
    raise exception 'User tenant not found';
  end if;

  perform public.validate_expense_report_range(
    v_tenant_id,
    p_start_date,
    p_end_date
  );

  return query
  select
    e.category_id,
    e.category_name,
    coalesce(sum(e.amount), 0)::numeric as total_amount,
    count(*)::bigint as entry_count
  from public.expenses e
  where e.tenant_id = v_tenant_id
    and e.status = 'confirmed'
    and e.expense_date between p_start_date and p_end_date
    and (p_branch_id is null or e.branch_id = p_branch_id)
    and (p_category_id is null or e.category_id = p_category_id)
    and (
      p_category_name is null
      or lower(e.category_name) = lower(p_category_name)
    )
  group by e.category_id, e.category_name
  order by total_amount desc;
end;
$$;

-- ---------------------------------------------------------
-- Profit integration
-- Adds cost columns to sale_items if missing.
-- This improves future COGS reporting.
-- Existing old rows will fallback to product cost_price.
-- ---------------------------------------------------------
alter table public.sale_items
add column if not exists unit_cost numeric;

alter table public.sale_items
add column if not exists cogs_total numeric;

create or replace function public.fill_sale_item_costs_and_line_total()
returns trigger
language plpgsql
as $$
declare
  v_cost numeric;
  v_gross numeric;
  v_discount numeric;
  v_tax_rate numeric;
begin
  select p.cost_price into v_cost
  from public.products p
  where p.id = new.product_id
  limit 1;

  new.unit_cost := coalesce(new.unit_cost, v_cost, 0);
  new.cogs_total := coalesce(
    new.cogs_total,
    coalesce(new.quantity, 0) * coalesce(new.unit_cost, 0)
  );

  v_gross := coalesce(new.quantity, 0) * coalesce(new.unit_price, 0);
  v_discount := coalesce(new.discount_amount, 0);
  v_tax_rate := coalesce(new.tax_rate, 0);

  new.line_total := coalesce(
    new.line_total,
    (v_gross - v_discount) + ((v_gross - v_discount) * v_tax_rate / 100)
  );

  return new;
end;
$$;

drop trigger if exists trg_fill_sale_item_costs_and_line_total
on public.sale_items;

create trigger trg_fill_sale_item_costs_and_line_total
before insert or update on public.sale_items
for each row
execute function public.fill_sale_item_costs_and_line_total();

-- ---------------------------------------------------------
-- RPC: Profit report
-- revenue - cogs - expenses = net_profit
-- ---------------------------------------------------------
create or replace function public.profit_report(
  p_start_date date,
  p_end_date date,
  p_branch_id uuid default null
)
returns table (
  total_revenue numeric,
  total_cogs numeric,
  gross_profit numeric,
  total_expenses numeric,
  net_profit numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.current_user_tenant_id();

  if v_tenant_id is null then
    raise exception 'User tenant not found';
  end if;

  perform public.validate_expense_report_range(
    v_tenant_id,
    p_start_date,
    p_end_date
  );

  return query
  with sales_summary as (
    select
      coalesce(sum(si.line_total), 0)::numeric as revenue,
      coalesce(
        sum(
          coalesce(
            si.cogs_total,
            si.quantity * coalesce(si.unit_cost, p.cost_price, 0)
          )
        ),
        0
      )::numeric as cogs
    from public.sales s
    join public.sale_items si on si.sale_id = s.id
    left join public.products p on p.id = si.product_id
    join public.branches b on b.id = s.branch_id
    where b.tenant_id = v_tenant_id
      and s.status = 'completed'
      and s.created_at::date between p_start_date and p_end_date
      and (p_branch_id is null or s.branch_id = p_branch_id)
  ),
  expense_summary as (
    select coalesce(sum(e.amount), 0)::numeric as expenses
    from public.expenses e
    where e.tenant_id = v_tenant_id
      and e.status = 'confirmed'
      and e.expense_date between p_start_date and p_end_date
      and (p_branch_id is null or e.branch_id = p_branch_id)
  )
  select
    ss.revenue as total_revenue,
    ss.cogs as total_cogs,
    (ss.revenue - ss.cogs) as gross_profit,
    es.expenses as total_expenses,
    (ss.revenue - ss.cogs - es.expenses) as net_profit
  from sales_summary ss, expense_summary es;
end;
$$;

-- ---------------------------------------------------------
-- RLS
-- ---------------------------------------------------------
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.recurring_expense_rules enable row level security;

drop policy if exists "tenant users can manage expense categories"
on public.expense_categories;

create policy "tenant users can manage expense categories"
on public.expense_categories
for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users can manage expenses"
on public.expenses;

create policy "tenant users can manage expenses"
on public.expenses
for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

drop policy if exists "tenant users can manage recurring expense rules"
on public.recurring_expense_rules;

create policy "tenant users can manage recurring expense rules"
on public.recurring_expense_rules
for all
using (tenant_id = public.current_user_tenant_id())
with check (tenant_id = public.current_user_tenant_id());

-- ---------------------------------------------------------
-- Storage RLS for expense receipts
-- tenant_id must be first folder in object path.
-- Example:
-- expense-receipts/{tenant_id}/{expense_id}/receipt.jpg
-- ---------------------------------------------------------
drop policy if exists "tenant users can upload expense receipts"
on storage.objects;

create policy "tenant users can upload expense receipts"
on storage.objects
for insert
with check (
  bucket_id = 'expense-receipts'
  and split_part(name, '/', 1)::uuid = public.current_user_tenant_id()
);

drop policy if exists "tenant users can read expense receipts"
on storage.objects;

create policy "tenant users can read expense receipts"
on storage.objects
for select
using (
  bucket_id = 'expense-receipts'
  and split_part(name, '/', 1)::uuid = public.current_user_tenant_id()
);

drop policy if exists "tenant users can update expense receipts"
on storage.objects;

create policy "tenant users can update expense receipts"
on storage.objects
for update
using (
  bucket_id = 'expense-receipts'
  and split_part(name, '/', 1)::uuid = public.current_user_tenant_id()
)
with check (
  bucket_id = 'expense-receipts'
  and split_part(name, '/', 1)::uuid = public.current_user_tenant_id()
);

drop policy if exists "tenant users can delete expense receipts"
on storage.objects;

create policy "tenant users can delete expense receipts"
on storage.objects
for delete
using (
  bucket_id = 'expense-receipts'
  and split_part(name, '/', 1)::uuid = public.current_user_tenant_id()
);

notify pgrst, 'reload schema';