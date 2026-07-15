-- Generate every overdue recurring occurrence, automatically confirm entries
-- whose due date has arrived, and retain only future reminder entries as draft.

drop function if exists public.generate_due_recurring_expenses(uuid, uuid);

create or replace function public.generate_due_recurring_expenses(
  p_tenant_id uuid,
  p_branch_id uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_created_count int := 0;
  v_rule record;
  v_due date;
begin
  if p_tenant_id <> public.current_user_tenant_id() then
    raise exception 'Not allowed';
  end if;

  update public.expenses
  set status = 'confirmed',
      confirmed_by = coalesce(confirmed_by, auth.uid()),
      confirmed_at = coalesce(confirmed_at, now()),
      updated_at = now()
  where tenant_id = p_tenant_id
    and branch_id = p_branch_id
    and source = 'recurring'
    and status = 'draft'
    and expense_date <= current_date;

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
    v_due := v_rule.next_due_date;

    while v_due <= current_date
      and (v_rule.end_date is null or v_due <= v_rule.end_date)
    loop
      insert into public.expenses (
        tenant_id, branch_id, category_id, category_name, title,
        expense_date, amount, payment_mode, payee, notes,
        status, source, recurring_rule_id, recurring_due_date, due_date,
        is_recurring_generated, created_by, confirmed_by, confirmed_at
      )
      values (
        v_rule.tenant_id, v_rule.branch_id, v_rule.category_id,
        v_rule.category_name,
        coalesce(v_rule.title, v_rule.category_name, 'Recurring Expense'),
        v_due, v_rule.estimated_amount, v_rule.payment_mode, v_rule.payee,
        v_rule.note, 'confirmed', 'recurring', v_rule.id, v_due, v_due,
        true, auth.uid(), auth.uid(), now()
      )
      on conflict do nothing;

      if found then
        v_created_count := v_created_count + 1;
      end if;

      v_due := public.advance_recurring_due_date(
        v_due, v_rule.frequency, v_rule.interval_count
      );
    end loop;

    update public.recurring_expense_rules
    set next_due_date = v_due,
        updated_at = now()
    where id = v_rule.id
      and tenant_id = p_tenant_id;
  end loop;

  return v_created_count;
end
$function$;

revoke all on function public.generate_due_recurring_expenses(uuid, uuid)
from public, anon;
grant execute on function public.generate_due_recurring_expenses(uuid, uuid)
to authenticated;
