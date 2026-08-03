-- Prevent duplicate account names within a branch without rewriting existing
-- financial accounts. Names are compared case-insensitively with whitespace
-- normalized, and inactive accounts remain reserved for ledger continuity.

-- Clean up only provably empty historical duplicates. The default/oldest row
-- is retained. Any duplicate with balance or ledger history remains untouched
-- for manual reconciliation.
with ranked_cash_accounts as (
  select
    account.id,
    row_number() over (
      partition by account.branch_id
      order by account.is_default desc, account.created_at asc, account.id asc
    ) as duplicate_rank
  from public.accounts account
  where account.is_active = true
    and lower(btrim(regexp_replace(account.name, '\s+', ' ', 'g'))) =
      'cash in shop'
), safe_duplicates as (
  select ranked.id
  from ranked_cash_accounts ranked
  join public.accounts account on account.id = ranked.id
  where ranked.duplicate_rank > 1
    and abs(account.current_balance) < 0.01
    and not exists (
      select 1
      from public.account_transactions transaction
      where transaction.account_id = account.id
    )
)
update public.accounts account
set
  name = btrim(account.name) || ' (Archived ' || left(account.id::text, 8) || ')',
  is_default = false,
  is_active = false,
  updated_at = now()
where account.id in (select id from safe_duplicates);

create or replace function public.prevent_duplicate_account_name()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_normalized_name text;
begin
  new.name := btrim(regexp_replace(new.name, '\s+', ' ', 'g'));
  if new.name = '' then
    raise exception 'ACCOUNT_NAME_REQUIRED';
  end if;

  v_normalized_name := lower(new.name);

  -- Serialize competing creates/renames for the same branch and normalized
  -- name so the application-level duplicate check cannot race.
  perform pg_advisory_xact_lock(
    hashtextextended(new.branch_id::text || ':' || v_normalized_name, 0)
  );

  if exists (
    select 1
    from public.accounts account
    where account.branch_id = new.branch_id
      and account.id <> new.id
      and lower(
        btrim(regexp_replace(account.name, '\s+', ' ', 'g'))
      ) = v_normalized_name
  ) then
    raise exception 'ACCOUNT_NAME_EXISTS';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_accounts_unique_name on public.accounts;
create trigger trg_accounts_unique_name
before insert or update of name, branch_id on public.accounts
for each row execute function public.prevent_duplicate_account_name();
