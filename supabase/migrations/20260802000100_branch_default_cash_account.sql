-- Allow an authorized branch user to atomically select the cash account used
-- by default for sales. Existing balances and ledger rows are untouched.

create or replace function public.set_default_cash_account(p_account_id uuid)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_account public.accounts%rowtype;
begin
  select *
  into v_account
  from public.accounts
  where id = p_account_id
    and is_active = true;

  if v_account.id is null then
    raise exception 'Account not found.';
  end if;

  if v_account.account_type <> 'cash' then
    raise exception 'Only a cash account can be the default cash account.';
  end if;

  update public.accounts
  set
    is_default = false,
    updated_at = now()
  where branch_id = v_account.branch_id
    and tenant_id = v_account.tenant_id
    and is_active = true
    and is_default = true;

  update public.accounts
  set
    is_default = true,
    updated_at = now()
  where id = p_account_id;
end;
$function$;

revoke all on function public.set_default_cash_account(uuid) from public;
revoke all on function public.set_default_cash_account(uuid) from anon;
grant execute on function public.set_default_cash_account(uuid) to authenticated;
