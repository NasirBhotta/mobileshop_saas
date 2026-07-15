-- Voiding is a final accounting action. Centralize it in an idempotent,
-- tenant-safe RPC and prevent stale offline upserts/confirmations from
-- reactivating a voided expense.

create or replace function public.prevent_voided_expense_reactivation()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  if old.status = 'void' and new.status <> 'void' then
    raise exception using
      errcode = '23514',
      message = 'Voided expense cannot be reactivated.';
  end if;
  return new;
end
$function$;

drop trigger if exists expenses_prevent_void_reactivation on public.expenses;
create trigger expenses_prevent_void_reactivation
before update of status on public.expenses
for each row execute function public.prevent_voided_expense_reactivation();

create or replace function public.void_expense(p_expense_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_tenant_id uuid := public.current_user_tenant_id();
begin
  if v_tenant_id is null then
    raise exception 'User tenant not found.';
  end if;

  update public.expenses
  set status = 'void',
      voided_by = auth.uid(),
      voided_at = coalesce(voided_at, now()),
      updated_at = now()
  where id = p_expense_id
    and tenant_id = v_tenant_id
    and status <> 'void';

  if found then
    return p_expense_id;
  end if;

  if exists (
    select 1
    from public.expenses
    where id = p_expense_id
      and tenant_id = v_tenant_id
      and status = 'void'
  ) then
    return p_expense_id;
  end if;

  raise exception 'Expense not found or not allowed.';
end
$function$;

revoke all on function public.void_expense(uuid) from public, anon;
grant execute on function public.void_expense(uuid) to authenticated;

revoke all on function public.prevent_voided_expense_reactivation()
from public, anon, authenticated;
