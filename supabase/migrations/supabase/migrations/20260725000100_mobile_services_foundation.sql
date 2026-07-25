create table public.mobile_service_providers (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null
    references public.tenants(id) on delete restrict,

  branch_id uuid not null
    references public.branches(id) on delete restrict,

  category text not null
    check (category in ('money_transfer')),

  code text not null
    check (code in ('easypaisa', 'jazzcash')),

  name text not null
    check (length(trim(name)) > 0),

  provider_account_id uuid not null
    references public.accounts(id) on delete restrict,

  is_active boolean not null default true,

  created_by uuid not null
    references public.users(id) on delete restrict,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  archived_at timestamptz,
  archived_by uuid
    references public.users(id) on delete restrict,

  unique (tenant_id, branch_id, category, code),

  check (
    (
      is_active = true
      and archived_at is null
      and archived_by is null
    )
    or
    (
      is_active = false
      and archived_at is not null
      and archived_by is not null
    )
  )
);


create table public.mobile_service_charge_rules (
  id uuid primary key default gen_random_uuid(),

  tenant_id uuid not null
    references public.tenants(id) on delete restrict,

  branch_id uuid not null
    references public.branches(id) on delete restrict,

  provider_id uuid not null
    references public.mobile_service_providers(id) on delete restrict,

  operation text not null
    check (operation in ('send', 'receive')),

  calculation_method text not null
    check (
      calculation_method in (
        'full_slab',
        'proportional',
        'fixed',
        'manual'
      )
    ),

  rate_amount numeric(12,2) not null default 0
    check (rate_amount >= 0),

  per_amount numeric(12,2)
    check (per_amount is null or per_amount > 0),

  minimum_fee numeric(12,2)
    check (minimum_fee is null or minimum_fee >= 0),

  maximum_fee numeric(12,2)
    check (maximum_fee is null or maximum_fee >= 0),

  is_active boolean not null default true,

  created_by uuid not null
    references public.users(id) on delete restrict,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  archived_at timestamptz,
  archived_by uuid
    references public.users(id) on delete restrict,

  unique (provider_id, operation),

  check (
    maximum_fee is null
    or minimum_fee is null
    or maximum_fee >= minimum_fee
  ),

  check (
    calculation_method not in ('full_slab', 'proportional')
    or per_amount is not null
  ),

  check (
    (
      is_active = true
      and archived_at is null
      and archived_by is null
    )
    or
    (
      is_active = false
      and archived_at is not null
      and archived_by is not null
    )
  )
);

create table public.mobile_service_transactions (
  id uuid primary key,

  tenant_id uuid not null
    references public.tenants(id) on delete restrict,

  branch_id uuid not null
    references public.branches(id) on delete restrict,

  provider_id uuid not null
    references public.mobile_service_providers(id) on delete restrict,

  charge_rule_id uuid
    references public.mobile_service_charge_rules(id) on delete restrict,

  service_category text not null
    check (service_category in ('money_transfer')),

  operation text not null
    check (operation in ('send', 'receive')),

  service_amount numeric(12,2) not null
    check (service_amount > 0),

  -- Applied rule snapshot
  calculation_method text not null
    check (
      calculation_method in (
        'full_slab',
        'proportional',
        'fixed',
        'manual'
      )
    ),

  applied_rate numeric(12,2) not null default 0
    check (applied_rate >= 0),

  applied_per_amount numeric(12,2)
    check (applied_per_amount is null or applied_per_amount > 0),

  calculated_fee numeric(12,2) not null
    check (calculated_fee >= 0),

  charged_fee numeric(12,2) not null
    check (charged_fee >= 0),

  customer_cash_amount numeric(12,2) not null
    check (customer_cash_amount >= 0),

  profit_amount numeric(12,2) not null
    check (profit_amount >= 0),

  cash_account_id uuid not null
    references public.accounts(id) on delete restrict,

  provider_account_id uuid not null
    references public.accounts(id) on delete restrict,

  -- Original ledger entries
  cash_ledger_transaction_id uuid unique
    references public.account_transactions(id) on delete restrict,

  provider_ledger_transaction_id uuid unique
    references public.account_transactions(id) on delete restrict,

  -- Reversal ledger entries
  cash_reversal_transaction_id uuid unique
    references public.account_transactions(id) on delete restrict,

  provider_reversal_transaction_id uuid unique
    references public.account_transactions(id) on delete restrict,

  phone_number text,
  reference_number text,
  description text,

  status text not null default 'completed'
    check (status in ('completed', 'voided')),

  transaction_at timestamptz not null default now(),

  created_by uuid not null
    references public.users(id) on delete restrict,

  created_at timestamptz not null default now(),

  voided_at timestamptz,
  voided_by uuid
    references public.users(id) on delete restrict,

  void_reason text,

  check (cash_account_id <> provider_account_id),

  check (
    operation <> 'receive'
    or charged_fee <= service_amount
  ),

  check (
    (
      status = 'completed'
      and voided_at is null
      and voided_by is null
      and void_reason is null
      and cash_reversal_transaction_id is null
      and provider_reversal_transaction_id is null
    )
    or
    (
      status = 'voided'
      and voided_at is not null
      and voided_by is not null
      and length(trim(void_reason)) > 0
      and cash_reversal_transaction_id is not null
      and provider_reversal_transaction_id is not null
    )
  )
);

