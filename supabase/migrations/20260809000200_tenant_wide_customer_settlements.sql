-- Customers are tenant-wide. A settlement belongs to the authorized branch
-- that receives the payment, and its account must still belong to that branch.
-- Patch the deployed function in place so all its idempotency, permission,
-- account-type, balance and ledger protections remain unchanged.

do $migration$
declare
  v_before text;
  v_after text;
begin
  select pg_get_functiondef(
    'public.commit_customer_settlement(jsonb)'::regprocedure
  ) into v_before;

  v_after := regexp_replace(
    v_before,
    E'or\\s+v_customer\\.branch_id\\s*<>\\s*v_branch_id\\s*',
    '',
    'i'
  );

  if v_after = v_before then
    if v_before ~* E'v_customer\\.branch_id\\s*<>\\s*v_branch_id' then
      raise exception 'Could not safely update customer settlement branch rule.';
    end if;
    -- The function is already on the tenant-wide customer rule.
    return;
  end if;

  execute v_after;
end
$migration$;

revoke all on function public.commit_customer_settlement(jsonb)
from public, anon;
grant execute on function public.commit_customer_settlement(jsonb)
to authenticated, service_role;
