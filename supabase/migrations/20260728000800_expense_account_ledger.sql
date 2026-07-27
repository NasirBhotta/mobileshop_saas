-- Post confirmed expenses to paying accounts and reverse them on void.

alter table public.expenses
  add column if not exists account_id uuid,
  add column if not exists ledger_transaction_id uuid,
  add column if not exists reversal_ledger_transaction_id uuid;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'expenses_account_id_fkey'
      and conrelid = 'public.expenses'::regclass
  ) then
    alter table public.expenses add constraint expenses_account_id_fkey
      foreign key (account_id) references public.accounts(id)
      on delete restrict not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'expenses_ledger_transaction_id_fkey'
      and conrelid = 'public.expenses'::regclass
  ) then
    alter table public.expenses
      add constraint expenses_ledger_transaction_id_fkey
      foreign key (ledger_transaction_id)
      references public.account_transactions(id)
      on delete restrict not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'expenses_reversal_ledger_transaction_id_fkey'
      and conrelid = 'public.expenses'::regclass
  ) then
    alter table public.expenses
      add constraint expenses_reversal_ledger_transaction_id_fkey
      foreign key (reversal_ledger_transaction_id)
      references public.account_transactions(id)
      on delete restrict not valid;
  end if;
end
$block$;

create unique index if not exists idx_expenses_ledger_transaction
  on public.expenses(ledger_transaction_id)
  where ledger_transaction_id is not null;
create unique index if not exists idx_expenses_reversal_ledger_transaction
  on public.expenses(reversal_ledger_transaction_id)
  where reversal_ledger_transaction_id is not null;

create or replace function public.commit_confirmed_expense(p_expense jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_id uuid := (p_expense->>'id')::uuid;
  v_tenant_id uuid := (p_expense->>'tenant_id')::uuid;
  v_branch_id uuid := (p_expense->>'branch_id')::uuid;
  v_account_id uuid := (p_expense->>'account_id')::uuid;
  v_ledger_id uuid := (p_expense->>'ledger_transaction_id')::uuid;
  v_amount numeric := (p_expense->>'amount')::numeric;
  v_mode text := lower(p_expense->>'payment_mode');
  v_expense public.expenses%rowtype;
  v_account public.accounts%rowtype;
  v_is_new boolean;
begin
  if v_id is null or v_tenant_id is null or v_branch_id is null
     or v_account_id is null or v_ledger_id is null
     or v_amount is null or v_amount <= 0 then
    raise exception using errcode = '22023',
      message = 'Confirmed expense identity, account, or amount is invalid.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));

  select expense.*
  into v_expense
  from public.expenses expense
  where expense.id = v_id
  for update;
  v_is_new := v_expense.id is null;

  if not public.current_user_has_branch_permission(
    v_tenant_id,
    v_branch_id,
    case when v_is_new
      then 'expense.expense.create'
      else 'expense.expense.update'
    end
  ) then
    raise exception using errcode = '42501',
      message = 'Expense create/update permission is required.';
  end if;

  if not v_is_new then
    if v_expense.tenant_id <> v_tenant_id
       or v_expense.branch_id <> v_branch_id
       or v_expense.status = 'void' then
      raise exception using errcode = '22023',
        message = 'Expense context is invalid or already voided.';
    end if;
    if v_expense.ledger_transaction_id is not null then
      if v_expense.account_id is distinct from v_account_id
         or v_expense.ledger_transaction_id is distinct from v_ledger_id
         or v_expense.amount is distinct from v_amount
         or v_expense.status <> 'confirmed' then
        raise exception using errcode = '23505',
          message = 'Expense ledger identity conflicts.';
      end if;
      return false;
    end if;
  end if;

  select account.*
  into v_account
  from public.accounts account
  where account.id = v_account_id
  for update;

  if v_account.id is null
     or v_account.tenant_id <> v_tenant_id
     or v_account.branch_id <> v_branch_id
     or not v_account.is_active
     or (v_mode = 'cash' and v_account.account_type <> 'cash')
     or (
       v_mode in ('easypaisa', 'jazzcash')
       and v_account.account_type <> 'mobile_wallet'
     )
     or (
       v_mode = 'card'
       and v_account.account_type not in ('card', 'bank')
     )
     or (
       v_mode in ('bank_transfer', 'cheque')
       and v_account.account_type <> 'bank'
     )
     or v_mode not in (
       'cash', 'card', 'bank_transfer', 'easypaisa', 'jazzcash',
       'cheque', 'other'
     ) then
    raise exception using errcode = '22023',
      message = 'Expense paying account is incompatible.';
  end if;

  if v_account.current_balance + 0.01 < v_amount then
    raise exception using errcode = '23514',
      message = 'Paying account balance is insufficient.';
  end if;

  if v_is_new then
    insert into public.expenses (
      id, tenant_id, branch_id, category_id, category_name, title,
      expense_date, amount, payment_mode, account_id,
      ledger_transaction_id, payee, notes, receipt_photo_path,
      local_receipt_path, status, source, recurring_rule_id,
      recurring_due_date, created_by, confirmed_by, confirmed_at,
      created_at, updated_at
    )
    values (
      v_id, v_tenant_id, v_branch_id,
      nullif(p_expense->>'category_id', '')::uuid,
      nullif(p_expense->>'category_name', ''),
      coalesce(nullif(p_expense->>'title', ''), 'Expense'),
      (p_expense->>'expense_date')::date,
      v_amount, v_mode, v_account_id, v_ledger_id,
      nullif(p_expense->>'payee', ''), nullif(p_expense->>'notes', ''),
      nullif(p_expense->>'receipt_photo_path', ''),
      nullif(p_expense->>'local_receipt_path', ''),
      'confirmed', coalesce(nullif(p_expense->>'source', ''), 'manual'),
      nullif(p_expense->>'recurring_rule_id', '')::uuid,
      nullif(p_expense->>'recurring_due_date', '')::date,
      auth.uid(), auth.uid(), now(),
      coalesce((p_expense->>'created_at')::timestamptz, now()), now()
    );
  else
    update public.expenses
    set amount = v_amount,
        payment_mode = v_mode,
        account_id = v_account_id,
        ledger_transaction_id = v_ledger_id,
        receipt_photo_path = coalesce(
          nullif(p_expense->>'receipt_photo_path', ''),
          receipt_photo_path
        ),
        status = 'confirmed',
        confirmed_by = auth.uid(),
        confirmed_at = coalesce(confirmed_at, now()),
        updated_at = now()
    where id = v_id;
  end if;

  insert into public.account_transactions (
    id, tenant_id, branch_id, account_id, transaction_type, direction,
    amount, description, reference_type, reference_id, source_event_key,
    transaction_at, created_by, created_at
  )
  values (
    v_ledger_id, v_tenant_id, v_branch_id, v_account_id, 'expense', 'out',
    v_amount, coalesce(nullif(p_expense->>'title', ''), 'Expense'),
    'expense', v_id::text, 'expense:' || v_id::text || ':confirm',
    now(), auth.uid(), now()
  );

  update public.accounts
  set current_balance = current_balance - v_amount,
      updated_at = now()
  where id = v_account_id;

  return true;
end
$function$;

create or replace function public.void_expense_with_reversal(
  p_expense_id uuid,
  p_reversal_ledger_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_expense public.expenses%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_expense_id::text, 0));
  select expense.*
  into v_expense
  from public.expenses expense
  where expense.id = p_expense_id
  for update;

  if v_expense.id is null or not public.current_user_has_branch_permission(
    v_expense.tenant_id,
    v_expense.branch_id,
    'expense.expense.void'
  ) then
    raise exception using errcode = '42501',
      message = 'Expense void permission is required.';
  end if;

  if v_expense.status = 'void' then
    if v_expense.reversal_ledger_transaction_id
       is distinct from p_reversal_ledger_id then
      raise exception using errcode = '23505',
        message = 'Expense reversal identity conflicts.';
    end if;
    return false;
  end if;

  if v_expense.status <> 'confirmed'
     or v_expense.account_id is null
     or v_expense.ledger_transaction_id is null
     or p_reversal_ledger_id is null then
    raise exception using errcode = '22023',
      message = 'Only a ledger-linked confirmed expense can be voided.';
  end if;

  insert into public.account_transactions (
    id, tenant_id, branch_id, account_id, transaction_type, direction,
    amount, description, reference_type, reference_id, source_event_key,
    reversal_of_transaction_id, transaction_at, created_by, created_at
  )
  values (
    p_reversal_ledger_id, v_expense.tenant_id, v_expense.branch_id,
    v_expense.account_id, 'expense', 'in', v_expense.amount,
    'Void: ' || v_expense.title, 'expense_void', v_expense.id::text,
    'expense:' || v_expense.id::text || ':void',
    v_expense.ledger_transaction_id, now(), auth.uid(), now()
  );

  update public.accounts
  set current_balance = current_balance + v_expense.amount,
      updated_at = now()
  where id = v_expense.account_id;

  update public.expenses
  set status = 'void', voided_by = auth.uid(), voided_at = now(),
      reversal_ledger_transaction_id = p_reversal_ledger_id,
      updated_at = now()
  where id = p_expense_id;

  return true;
end
$function$;

revoke all on function public.commit_confirmed_expense(jsonb)
from public, anon;
grant execute on function public.commit_confirmed_expense(jsonb)
to authenticated, service_role;
revoke all on function public.void_expense_with_reversal(uuid, uuid)
from public, anon;
grant execute on function public.void_expense_with_reversal(uuid, uuid)
to authenticated, service_role;
