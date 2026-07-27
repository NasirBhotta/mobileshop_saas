-- Canonical source-event identity and auditable reversal foundation.
-- Existing rows remain valid: both new fields are nullable and no backfill is
-- attempted.

alter table public.account_transactions
add column if not exists source_event_key text;

alter table public.account_transactions
add column if not exists reversal_of_transaction_id uuid;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.account_transactions'::regclass
      and conname = 'account_transactions_source_event_not_blank'
  ) then
    alter table public.account_transactions
    add constraint account_transactions_source_event_not_blank
    check (
      source_event_key is null
      or btrim(source_event_key) <> ''
    );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.account_transactions'::regclass
      and conname = 'account_transactions_not_self_reversal'
  ) then
    alter table public.account_transactions
    add constraint account_transactions_not_self_reversal
    check (
      reversal_of_transaction_id is null
      or reversal_of_transaction_id <> id
    );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.account_transactions'::regclass
      and conname = 'account_transactions_reversal_fk'
  ) then
    alter table public.account_transactions
    add constraint account_transactions_reversal_fk
    foreign key (reversal_of_transaction_id)
    references public.account_transactions(id)
    on delete restrict;
  end if;
end;
$block$;

create unique index if not exists
uq_account_transactions_source_event
on public.account_transactions(tenant_id, branch_id, source_event_key)
where source_event_key is not null;

create unique index if not exists
uq_account_transactions_reversal
on public.account_transactions(reversal_of_transaction_id)
where reversal_of_transaction_id is not null;

create index if not exists
idx_account_transactions_reference
on public.account_transactions(
  tenant_id,
  branch_id,
  reference_type,
  reference_id
);

create or replace function public.record_account_transaction_v2(
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
  p_source_event_key text default null,
  p_reversal_of_transaction_id uuid default null,
  p_transaction_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.accounts%rowtype;
  v_original public.account_transactions%rowtype;
  v_existing_id uuid;
  v_inserted_id uuid;
  v_delta numeric;
begin
  if p_transaction_id is null then
    raise exception 'Transaction ID is required.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero.';
  end if;

  if p_direction not in ('in', 'out') then
    raise exception 'Transaction direction is invalid.';
  end if;

  if p_source_event_key is not null
     and btrim(p_source_event_key) = '' then
    raise exception 'Source event key cannot be blank.';
  end if;

  if p_reversal_of_transaction_id = p_transaction_id then
    raise exception 'A ledger entry cannot reverse itself.';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.tenant_id = p_tenant_id
  ) then
    raise exception 'Not allowed.';
  end if;

  if not public.current_user_has_branch_permission(
    p_tenant_id,
    p_branch_id,
    'account.transaction.create'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Account transaction permission is required.';
  end if;

  if p_source_event_key is not null then
    perform pg_advisory_xact_lock(
      hashtext(
        p_tenant_id::text || ':' ||
        p_branch_id::text || ':' ||
        p_source_event_key
      )
    );

    select t.id
    into v_existing_id
    from public.account_transactions t
    where t.tenant_id = p_tenant_id
      and t.branch_id = p_branch_id
      and t.source_event_key = p_source_event_key
    limit 1;

    if v_existing_id is not null then
      return v_existing_id;
    end if;
  end if;

  if exists (
    select 1
    from public.account_transactions t
    where t.id = p_transaction_id
  ) then
    return p_transaction_id;
  end if;

  select a.*
  into v_account
  from public.accounts a
  where a.id = p_account_id
  for update;

  if v_account.id is null
     or v_account.tenant_id <> p_tenant_id
     or v_account.branch_id <> p_branch_id
     or not v_account.is_active then
    raise exception 'Account not found.';
  end if;

  if p_reversal_of_transaction_id is not null then
    select t.*
    into v_original
    from public.account_transactions t
    where t.id = p_reversal_of_transaction_id
    for update;

    if v_original.id is null then
      raise exception 'Original ledger entry was not found.';
    end if;

    if v_original.tenant_id <> p_tenant_id
       or v_original.branch_id <> p_branch_id
       or v_original.account_id <> p_account_id then
      raise exception 'Reversal ledger context does not match.';
    end if;

    if v_original.reversal_of_transaction_id is not null then
      raise exception 'A reversal entry cannot be reversed.';
    end if;

    if v_original.amount <> p_amount
       or v_original.direction = p_direction then
      raise exception
        'Reversal must use the original amount and opposite direction.';
    end if;

    if exists (
      select 1
      from public.account_transactions t
      where t.reversal_of_transaction_id = p_reversal_of_transaction_id
    ) then
      raise exception 'Ledger entry has already been reversed.';
    end if;
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
    source_event_key,
    reversal_of_transaction_id,
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
    p_source_event_key,
    p_reversal_of_transaction_id,
    coalesce(p_transaction_at, now()),
    auth.uid()
  )
  returning id into v_inserted_id;

  update public.accounts
  set current_balance = current_balance + v_delta
  where id = p_account_id;

  return v_inserted_id;
end;
$$;

revoke all on function public.record_account_transaction_v2(
  uuid, uuid, uuid, uuid, text, text, numeric, text, text, text, text, uuid,
  timestamptz
) from public, anon;

grant execute on function public.record_account_transaction_v2(
  uuid, uuid, uuid, uuid, text, text, numeric, text, text, text, text, uuid,
  timestamptz
) to authenticated;
