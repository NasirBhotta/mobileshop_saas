-- Recurring expenses must use the same account ledger as manual expenses.

alter table public.recurring_expense_rules
  add column if not exists account_id uuid;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'recurring_expense_rules_account_id_fkey'
      and conrelid = 'public.recurring_expense_rules'::regclass
  ) then
    alter table public.recurring_expense_rules
      add constraint recurring_expense_rules_account_id_fkey
      foreign key (account_id) references public.accounts(id)
      on delete restrict not valid;
  end if;
end
$block$;

create index if not exists idx_recurring_expense_rules_account
  on public.recurring_expense_rules(account_id)
  where account_id is not null;

create or replace function public.generate_due_recurring_expenses(
  p_tenant_id uuid,
  p_branch_id uuid
)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_created_count int := 0;
  v_rule record;
  v_account public.accounts%rowtype;
  v_due date;
  v_expense_id uuid;
  v_ledger_id uuid;
begin
  if p_tenant_id <> public.current_user_tenant_id() then
    raise exception using errcode = '42501', message = 'Not allowed';
  end if;

  for v_rule in
    select *
    from public.recurring_expense_rules
    where tenant_id = p_tenant_id
      and branch_id = p_branch_id
      and status = 'active'
      and next_due_date <= current_date
      and (end_date is null or next_due_date <= end_date)
    for update
  loop
    if v_rule.account_id is null then
      raise exception using errcode = '22023',
        message = 'Recurring expense paying account is required.';
    end if;

    select account.*
    into v_account
    from public.accounts account
    where account.id = v_rule.account_id
    for update;

    if v_account.id is null
       or v_account.tenant_id <> v_rule.tenant_id
       or v_account.branch_id <> v_rule.branch_id
       or not v_account.is_active
       or (v_rule.payment_mode = 'cash' and v_account.account_type <> 'cash')
       or (
         v_rule.payment_mode in ('easypaisa', 'jazzcash')
         and v_account.account_type <> 'mobile_wallet'
       )
       or (
         v_rule.payment_mode = 'card'
         and v_account.account_type not in ('card', 'bank')
       )
       or (
         v_rule.payment_mode in ('bank_transfer', 'cheque')
         and v_account.account_type <> 'bank'
       ) then
      raise exception using errcode = '22023',
        message = 'Recurring expense paying account is incompatible.';
    end if;

    v_due := v_rule.next_due_date;
    while v_due <= current_date
      and (v_rule.end_date is null or v_due <= v_rule.end_date)
    loop
      if not exists (
        select 1 from public.expenses
        where recurring_rule_id = v_rule.id
          and recurring_due_date = v_due
      ) then
        if v_account.current_balance + 0.01 < v_rule.estimated_amount then
          raise exception using errcode = '23514',
            message = 'Recurring expense paying account balance is insufficient.';
        end if;

        v_expense_id := gen_random_uuid();
        v_ledger_id := gen_random_uuid();

        insert into public.account_transactions (
          id, tenant_id, branch_id, account_id, transaction_type, direction,
          amount, description, reference_type, reference_id, source_event_key,
          transaction_at, created_by, created_at
        )
        values (
          v_ledger_id, v_rule.tenant_id, v_rule.branch_id, v_rule.account_id,
          'expense', 'out', v_rule.estimated_amount,
          coalesce(v_rule.title, v_rule.category_name, 'Recurring Expense'),
          'expense', v_expense_id::text,
          'expense:' || v_expense_id::text || ':confirm',
          now(), auth.uid(), now()
        );

        insert into public.expenses (
          id, tenant_id, branch_id, category_id, category_name, title,
          expense_date, amount, payment_mode, account_id,
          ledger_transaction_id, payee, notes, status, source,
          recurring_rule_id, recurring_due_date, due_date,
          is_recurring_generated, created_by, confirmed_by, confirmed_at
        )
        values (
          v_expense_id, v_rule.tenant_id, v_rule.branch_id, v_rule.category_id,
          v_rule.category_name,
          coalesce(v_rule.title, v_rule.category_name, 'Recurring Expense'),
          v_due, v_rule.estimated_amount, v_rule.payment_mode,
          v_rule.account_id, v_ledger_id, v_rule.payee, v_rule.note,
          'confirmed', 'recurring', v_rule.id, v_due, v_due, true,
          auth.uid(), auth.uid(), now()
        );

        update public.accounts
        set current_balance = current_balance - v_rule.estimated_amount,
            updated_at = now()
        where id = v_rule.account_id
        returning * into v_account;

        v_created_count := v_created_count + 1;
      end if;

      v_due := public.advance_recurring_due_date(
        v_due, v_rule.frequency, v_rule.interval_count
      );
    end loop;

    update public.recurring_expense_rules
    set next_due_date = v_due, updated_at = now()
    where id = v_rule.id and tenant_id = p_tenant_id;
  end loop;

  return v_created_count;
end
$function$;

revoke all on function public.generate_due_recurring_expenses(uuid, uuid)
from public, anon;
grant execute on function public.generate_due_recurring_expenses(uuid, uuid)
to authenticated, service_role;
