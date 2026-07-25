-- Mobile services foundation.
-- Phase 1 supports Easypaisa/JazzCash money transfer. The provider/category
-- model intentionally leaves room for mobile load without mixing load costing
-- into the first release.

-- Composite keys let PostgreSQL enforce tenant + branch consistency rather
-- than relying only on application code.
do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'branches_id_tenant_unique'
      and conrelid = 'public.branches'::regclass
  ) then
    alter table public.branches
      add constraint branches_id_tenant_unique unique (id, tenant_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'accounts_id_tenant_branch_unique'
      and conrelid = 'public.accounts'::regclass
  ) then
    alter table public.accounts
      add constraint accounts_id_tenant_branch_unique
      unique (id, tenant_id, branch_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'users_id_tenant_unique'
      and conrelid = 'public.users'::regclass
  ) then
    alter table public.users
      add constraint users_id_tenant_unique unique (id, tenant_id);
  end if;
end
$block$;

create or replace function public.current_user_can_access_branch(
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select exists (
    select 1
    from public.users u
    join public.branches b
      on b.id = p_branch_id
     and b.tenant_id = u.tenant_id
    where u.id = auth.uid()
      and u.is_active = true
      and u.deleted_at is null
      and u.tenant_id is not null
      and (
        u.role = 'owner'
        or u.branch_id = p_branch_id
      )
  );
$function$;

revoke all on function public.current_user_can_access_branch(uuid)
from public, anon;
grant execute on function public.current_user_can_access_branch(uuid)
to authenticated, service_role;

create table public.mobile_service_providers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  category text not null
    check (category in ('money_transfer')),
  code text not null
    check (code in ('easypaisa', 'jazzcash')),
  name text not null check (length(trim(name)) > 0),
  provider_account_id uuid not null,
  is_active boolean not null default true,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  archived_by uuid references public.users(id) on delete restrict,
  constraint mobile_service_providers_branch_scope_fk
    foreign key (branch_id, tenant_id)
    references public.branches(id, tenant_id)
    on delete restrict,
  constraint mobile_service_providers_account_scope_fk
    foreign key (provider_account_id, tenant_id, branch_id)
    references public.accounts(id, tenant_id, branch_id)
    on delete restrict,
  constraint mobile_service_providers_creator_scope_fk
    foreign key (created_by, tenant_id)
    references public.users(id, tenant_id)
    on delete restrict,
  constraint mobile_service_providers_archiver_scope_fk
    foreign key (archived_by, tenant_id)
    references public.users(id, tenant_id)
    on delete restrict,
  constraint mobile_service_providers_scope_unique
    unique (id, tenant_id, branch_id),
  constraint mobile_service_providers_code_unique
    unique (tenant_id, branch_id, category, code),
  constraint mobile_service_providers_archive_check
    check (
      (
        is_active
        and archived_at is null
        and archived_by is null
      )
      or
      (
        not is_active
        and archived_at is not null
        and archived_by is not null
      )
    )
);

create table public.mobile_service_charge_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  provider_id uuid not null,
  operation text not null check (operation in ('send', 'receive')),
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
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  archived_by uuid references public.users(id) on delete restrict,
  constraint mobile_service_rules_provider_scope_fk
    foreign key (provider_id, tenant_id, branch_id)
    references public.mobile_service_providers(id, tenant_id, branch_id)
    on delete restrict,
  constraint mobile_service_rules_creator_scope_fk
    foreign key (created_by, tenant_id)
    references public.users(id, tenant_id)
    on delete restrict,
  constraint mobile_service_rules_archiver_scope_fk
    foreign key (archived_by, tenant_id)
    references public.users(id, tenant_id)
    on delete restrict,
  constraint mobile_service_rules_scope_unique
    unique (id, tenant_id, branch_id, provider_id),
  constraint mobile_service_rules_operation_unique
    unique (provider_id, operation),
  constraint mobile_service_rules_limits_check
    check (
      maximum_fee is null
      or minimum_fee is null
      or maximum_fee >= minimum_fee
    ),
  constraint mobile_service_rules_slab_check
    check (
      calculation_method not in ('full_slab', 'proportional')
      or per_amount is not null
    ),
  constraint mobile_service_rules_archive_check
    check (
      (
        is_active
        and archived_at is null
        and archived_by is null
      )
      or
      (
        not is_active
        and archived_at is not null
        and archived_by is not null
      )
    )
);

create table public.mobile_service_transactions (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  provider_id uuid not null,
  charge_rule_id uuid references public.mobile_service_charge_rules(id)
    on delete restrict,
  service_category text not null
    check (service_category in ('money_transfer')),
  operation text not null check (operation in ('send', 'receive')),
  service_amount numeric(12,2) not null check (service_amount > 0),

  -- Snapshot of the rule used at transaction time.
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
  calculated_fee numeric(12,2) not null check (calculated_fee >= 0),
  charged_fee numeric(12,2) not null check (charged_fee >= 0),
  customer_cash_amount numeric(12,2) not null
    check (customer_cash_amount >= 0),
  profit_amount numeric(12,2) not null check (profit_amount >= 0),

  cash_account_id uuid not null,
  provider_account_id uuid not null,
  cash_ledger_transaction_id uuid not null unique
    references public.account_transactions(id) on delete restrict,
  provider_ledger_transaction_id uuid not null unique
    references public.account_transactions(id) on delete restrict,
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
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references public.users(id) on delete restrict,
  void_reason text,

  constraint mobile_service_transactions_provider_scope_fk
    foreign key (provider_id, tenant_id, branch_id)
    references public.mobile_service_providers(id, tenant_id, branch_id)
    on delete restrict,
  constraint mobile_service_transactions_rule_scope_fk
    foreign key (charge_rule_id, tenant_id, branch_id, provider_id)
    references public.mobile_service_charge_rules(
      id, tenant_id, branch_id, provider_id
    )
    on delete restrict,
  constraint mobile_service_transactions_cash_scope_fk
    foreign key (cash_account_id, tenant_id, branch_id)
    references public.accounts(id, tenant_id, branch_id)
    on delete restrict,
  constraint mobile_service_transactions_wallet_scope_fk
    foreign key (provider_account_id, tenant_id, branch_id)
    references public.accounts(id, tenant_id, branch_id)
    on delete restrict,
  constraint mobile_service_transactions_accounts_different
    check (cash_account_id <> provider_account_id),
  constraint mobile_service_transactions_creator_scope_fk
    foreign key (created_by, tenant_id)
    references public.users(id, tenant_id)
    on delete restrict,
  constraint mobile_service_transactions_void_actor_scope_fk
    foreign key (voided_by, tenant_id)
    references public.users(id, tenant_id)
    on delete restrict,
  constraint mobile_service_transactions_receive_fee_check
    check (operation <> 'receive' or charged_fee < service_amount),
  constraint mobile_service_transactions_void_check
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

create index mobile_service_providers_branch_idx
on public.mobile_service_providers (tenant_id, branch_id, is_active);

create index mobile_service_rules_lookup_idx
on public.mobile_service_charge_rules (
  tenant_id, branch_id, provider_id, operation
)
where is_active;

create index mobile_service_transactions_branch_date_idx
on public.mobile_service_transactions (
  tenant_id, branch_id, transaction_at desc
);

create index mobile_service_transactions_provider_date_idx
on public.mobile_service_transactions (provider_id, transaction_at desc);

create index mobile_service_transactions_profit_idx
on public.mobile_service_transactions (
  tenant_id, branch_id, transaction_at desc
)
where status = 'completed';

create index mobile_service_transactions_actor_idx
on public.mobile_service_transactions (
  tenant_id, branch_id, created_by, transaction_at desc
);

create trigger mobile_service_providers_updated_at
before update on public.mobile_service_providers
for each row execute function public.touch_updated_at();

create trigger mobile_service_rules_updated_at
before update on public.mobile_service_charge_rules
for each row execute function public.touch_updated_at();

alter table public.mobile_service_providers enable row level security;
alter table public.mobile_service_charge_rules enable row level security;
alter table public.mobile_service_transactions enable row level security;

revoke all on table public.mobile_service_providers
from anon, authenticated;
revoke all on table public.mobile_service_charge_rules
from anon, authenticated;
revoke all on table public.mobile_service_transactions
from anon, authenticated;

grant select on table public.mobile_service_providers to authenticated;
grant select on table public.mobile_service_charge_rules to authenticated;
grant select on table public.mobile_service_transactions to authenticated;

-- No INSERT/UPDATE/DELETE policy is intentionally created. Mutations are
-- available only through the security-definer RPCs in later migrations.
create policy "mobile service providers branch read"
on public.mobile_service_providers
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and public.current_user_can_access_branch(branch_id)
);

create policy "mobile service rules branch read"
on public.mobile_service_charge_rules
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and public.current_user_can_access_branch(branch_id)
);

create policy "mobile service transactions branch read"
on public.mobile_service_transactions
for select to authenticated
using (
  tenant_id = public.current_user_tenant_id()
  and public.current_user_can_access_branch(branch_id)
);
