-- Account/cashbook module.
-- Keeps shop cash, bank, wallet balances and an auditable ledger.

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  name text not null,
  account_type text not null default 'cash'
    check (account_type in ('cash', 'bank', 'mobile_wallet', 'card', 'other')),
  opening_balance numeric(12,2) not null default 0,
  current_balance numeric(12,2) not null default 0,
  is_default boolean not null default false,
  is_active boolean not null default true,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists accounts_default_per_branch
on public.accounts(branch_id)
where is_default = true and is_active = true;

create index if not exists idx_accounts_tenant
on public.accounts(tenant_id);

create index if not exists idx_accounts_branch
on public.accounts(branch_id);

create table if not exists public.account_transactions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete restrict,
  related_account_id uuid references public.accounts(id) on delete set null,
  transfer_group_id uuid,
  transaction_type text not null
    check (
      transaction_type in (
        'opening_balance',
        'sale',
        'customer_payment',
        'supplier_payment',
        'expense',
        'purchase',
        'transfer_in',
        'transfer_out',
        'adjustment',
        'other'
      )
    ),
  direction text not null check (direction in ('in', 'out')),
  amount numeric(12,2) not null check (amount > 0),
  description text,
  reference_type text,
  reference_id text,
  transaction_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_account_transactions_tenant
on public.account_transactions(tenant_id);

create index if not exists idx_account_transactions_branch_date
on public.account_transactions(branch_id, transaction_at desc);

create index if not exists idx_account_transactions_account_date
on public.account_transactions(account_id, transaction_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_accounts_updated_at on public.accounts;
create trigger trg_accounts_updated_at
before update on public.accounts
for each row execute function public.touch_updated_at();

create or replace function public.record_account_transaction(
  p_transaction_id uuid,
  p_tenant_id uuid,
  p_branch_id uuid,
  p_account_id uuid,
  p_transaction_type text,
  p_direction text,
  p_amount numeric,
  p_description text default null,
  p_reference_type text default null,
  p_reference_id text default null,
  p_transaction_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_delta numeric;
  v_inserted uuid;
begin
  if p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = p_tenant_id
  ) then
    raise exception 'Not allowed';
  end if;

  if not exists (
    select 1
    from public.accounts a
    where a.id = p_account_id
      and a.tenant_id = p_tenant_id
      and a.branch_id = p_branch_id
      and a.is_active = true
  ) then
    raise exception 'Account not found';
  end if;

  v_delta := case when p_direction = 'in' then p_amount else -p_amount end;

  insert into public.account_transactions (
    id,
    tenant_id,
    branch_id,
    account_id,
    transaction_type,
    direction,
    amount,
    description,
    reference_type,
    reference_id,
    transaction_at,
    created_by
  )
  values (
    p_transaction_id,
    p_tenant_id,
    p_branch_id,
    p_account_id,
    p_transaction_type,
    p_direction,
    p_amount,
    p_description,
    p_reference_type,
    p_reference_id,
    coalesce(p_transaction_at, now()),
    auth.uid()
  )
  on conflict (id) do nothing
  returning id into v_inserted;

  if v_inserted is not null then
    update public.accounts
    set current_balance = current_balance + v_delta
    where id = p_account_id;
  end if;

  return p_transaction_id;
end;
$$;

create or replace function public.record_account_transfer(
  p_out_transaction_id uuid,
  p_in_transaction_id uuid,
  p_tenant_id uuid,
  p_branch_id uuid,
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_transfer_group_id uuid,
  p_amount numeric,
  p_description text default null,
  p_transaction_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_out_inserted uuid;
  v_in_inserted uuid;
begin
  if p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = p_tenant_id
  ) then
    raise exception 'Not allowed';
  end if;

  if p_from_account_id = p_to_account_id then
    raise exception 'Select two different accounts';
  end if;

  if not exists (
    select 1
    from public.accounts a
    where a.id in (p_from_account_id, p_to_account_id)
      and a.tenant_id = p_tenant_id
      and a.branch_id = p_branch_id
      and a.is_active = true
    group by a.tenant_id
    having count(*) = 2
  ) then
    raise exception 'Account not found';
  end if;

  insert into public.account_transactions (
    id,
    tenant_id,
    branch_id,
    account_id,
    related_account_id,
    transfer_group_id,
    transaction_type,
    direction,
    amount,
    description,
    transaction_at,
    created_by
  )
  values (
    p_out_transaction_id,
    p_tenant_id,
    p_branch_id,
    p_from_account_id,
    p_to_account_id,
    p_transfer_group_id,
    'transfer_out',
    'out',
    p_amount,
    p_description,
    coalesce(p_transaction_at, now()),
    auth.uid()
  )
  on conflict (id) do nothing
  returning id into v_out_inserted;

  insert into public.account_transactions (
    id,
    tenant_id,
    branch_id,
    account_id,
    related_account_id,
    transfer_group_id,
    transaction_type,
    direction,
    amount,
    description,
    transaction_at,
    created_by
  )
  values (
    p_in_transaction_id,
    p_tenant_id,
    p_branch_id,
    p_to_account_id,
    p_from_account_id,
    p_transfer_group_id,
    'transfer_in',
    'in',
    p_amount,
    p_description,
    coalesce(p_transaction_at, now()),
    auth.uid()
  )
  on conflict (id) do nothing
  returning id into v_in_inserted;

  if v_out_inserted is not null then
    update public.accounts
    set current_balance = current_balance - p_amount
    where id = p_from_account_id;
  end if;

  if v_in_inserted is not null then
    update public.accounts
    set current_balance = current_balance + p_amount
    where id = p_to_account_id;
  end if;

  return coalesce(p_transfer_group_id, gen_random_uuid());
end;
$$;

alter table public.accounts enable row level security;
alter table public.account_transactions enable row level security;

drop policy if exists "tenant users can manage accounts"
on public.accounts;

create policy "tenant users can manage accounts"
on public.accounts
for all
using (tenant_id in (select tenant_id from public.users where id = auth.uid()))
with check (tenant_id in (select tenant_id from public.users where id = auth.uid()));

drop policy if exists "tenant users can manage account transactions"
on public.account_transactions;

create policy "tenant users can manage account transactions"
on public.account_transactions
for all
using (tenant_id in (select tenant_id from public.users where id = auth.uid()))
with check (tenant_id in (select tenant_id from public.users where id = auth.uid()));
